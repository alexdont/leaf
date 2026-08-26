"use strict";

// List editing, against a real DOM.
//
// Every case here is a bug that shipped: each one passed a green stubbed suite
// because the defect was in DOM work a stub replaces. The rule they encode,
// and the one to keep in mind when changing any of this:
//
//   Enter and blur tidy away an empty bullet ONLY as the last item of a list.
//   With items below, the blank row is one the author is deliberately keeping,
//   and removing it means a list can never contain an empty line.
//
// Both editing modes get the same treatment, because they are separate code
// paths that were fixed separately: visual goes through `_onVisualKeydown`,
// hybrid intercepts first in `_maybeHandleSourceEnter` and re-renders blocks
// from markdown in `_exitSourceMode`.

const test = require("node:test");
const assert = require("node:assert/strict");

const dom = require("./support/dom.cjs");
const { skip, editor, caretAtEndOf, pressEnter, readable, ZWSP } = dom;

const items = (e) => e._visualEl.querySelectorAll("li");
const texts = (e) => Array.from(items(e)).map((li) => li.textContent.split(ZWSP).join(""));

// --------------------------------------------------------------------------
// Visual mode
// --------------------------------------------------------------------------

test("visual: Enter on an empty item mid-list keeps it and adds one", { skip }, () => {
  const e = editor(`<ul><li>one</li><li>${ZWSP}</li><li>three</li></ul>`);
  const target = items(e)[1];

  e._getCurrentBlock = () => target;
  caretAtEndOf(target);
  pressEnter(e);

  assert.equal(items(e).length, 4, readable(e._visualEl));
  assert.deepEqual(texts(e), ["one", "", "", "three"]);
  e.cleanup();
});

test("visual: Enter on an empty item at the end exits the list", { skip }, () => {
  // The only keyboard way out of a list; it must survive the rule above.
  const e = editor(`<ul><li>one</li><li>two</li><li>${ZWSP}</li></ul>`);
  const target = items(e)[2];

  e._getCurrentBlock = () => target;
  caretAtEndOf(target);
  pressEnter(e);

  assert.equal(items(e).length, 2);
  assert.match(e._visualEl.innerHTML, /<p><br><\/p>$/);
  e.cleanup();
});

test("visual: a bullet made by splitting is not born invisible", { skip }, () => {
  // `Range.extractContents()` returns a fragment holding an EMPTY TEXT NODE
  // when the caret sat at the end of a line, so the old `!newLi.firstChild`
  // check read the new item as occupied, skipped its placeholder, and left it
  // rendering at zero height with no home for the caret.
  const e = editor(`<ul><li>one</li><li>two</li><li>three</li></ul>`);
  const target = items(e)[1];

  e._getCurrentBlock = () => target;
  caretAtEndOf(target);
  pressEnter(e);

  const fresh = items(e)[2];

  assert.equal(items(e).length, 4);
  assert.ok(
    fresh.textContent.includes(ZWSP),
    "the new item needs a caret home, got: " + readable(e._visualEl)
  );
  e.cleanup();
});

// --------------------------------------------------------------------------
// Hybrid mode — Enter
// --------------------------------------------------------------------------

// A source-mode item shows its markdown, so "empty" means "only the marker".
const source = (marker) => `<li data-leaf-source="li">${marker}</li>`;

function hybridEnter(html, index) {
  const e = editor(html, "hybrid");
  const target = items(e)[index];

  e._sourceBlock = target;
  caretAtEndOf(target);

  const handled = e._maybeHandleSourceEnter();
  return { e, handled };
}

test("hybrid: Enter on an empty item mid-list keeps it and adds one", { skip }, () => {
  const { e } = hybridEnter(`<ul><li>one</li>${source("- ")}<li>three</li></ul>`, 1);

  assert.equal(items(e).length, 4, readable(e._visualEl));
  e.cleanup();
});

test("hybrid: Enter on an empty item at the end exits the list", { skip }, () => {
  const { e } = hybridEnter(`<ul><li>one</li>${source("- ")}</ul>`, 1);

  assert.equal(items(e).length, 1);
  assert.match(e._visualEl.innerHTML, /<p><br><\/p>/);
  e.cleanup();
});

// --------------------------------------------------------------------------
// Hybrid mode — leaving the block
// --------------------------------------------------------------------------

function leaveBlock(html, index) {
  const e = editor(html, "hybrid");
  const target = items(e)[index];

  e._renderListItemFromSource = (src) => {
    const li = document.createElement("li");
    const body = src.replace(/^(- |\d+\. )/, "");
    if (body) li.appendChild(document.createTextNode(body));
    return li;
  };
  e._renderBlockFromSource = () => document.createElement("p");
  e._exitListItemToParagraph = () => {};

  e._exitSourceMode(target);
  return e;
}

test("hybrid: an empty item mid-list survives the caret leaving", { skip }, () => {
  // This was the reported bug: the row could not be left empty at all, because
  // it was removed the moment the caret moved away.
  const e = leaveBlock(`<ul><li>one</li>${source("- ")}<li>three</li></ul>`, 1);

  assert.equal(items(e).length, 3, readable(e._visualEl));
  e.cleanup();
});

test("hybrid: an empty item at the end is still tidied away", { skip }, () => {
  // A trailing bullet is the residue of starting an item and changing your
  // mind. Clearing it is the point of the tidy-up, and stays.
  const e = leaveBlock(`<ul><li>one</li><li>two</li>${source("- ")}</ul>`, 2);

  assert.equal(items(e).length, 2);
  e.cleanup();
});

test("hybrid: an item with content is never dropped", { skip }, () => {
  const e = leaveBlock(`<ul><li>one</li>${source("- two")}<li>three</li></ul>`, 1);

  assert.equal(items(e).length, 3);
  e.cleanup();
});

// --------------------------------------------------------------------------
// Two lists that read as one.
//
// Editing produces adjacent lists more easily than it looks. Deleting an
// item's `- ` marker breaks that item out to a paragraph and moves everything
// below it into a SECOND list; delete the paragraph and the two close up
// against each other, rendering as the single continuous list the author sees.
//
// A blank row at the end of the first list then had no next sibling, so the
// tidy-up removed it while bullets were plainly visible underneath — the
// "sometimes" in the report, and why it looked like nothing was checking what
// followed.
// --------------------------------------------------------------------------

function afterLeaving(html, index) {
  const e = editor(html, "hybrid");

  e._renderListItemFromSource = (src) => {
    const li = document.createElement("li");
    const body = src.replace(/^(- |\d+\. )/, "");
    if (body) li.appendChild(document.createTextNode(body));
    return li;
  };
  e._renderBlockFromSource = () => document.createElement("p");
  e._exitListItemToParagraph = () => {};

  const before = items(e).length;
  e._exitSourceMode(items(e)[index]);
  const after = items(e).length;

  e.cleanup();
  return { before, after, kept: before === after };
}

test("hybrid: a blank row survives when another list follows immediately", { skip }, () => {
  const r = afterLeaving(`<ul><li>one</li>${source("- ")}</ul><ul><li>three</li></ul>`, 1);

  assert.ok(r.kept, `expected the row to be kept, went ${r.before} -> ${r.after}`);
});

test("hybrid: a paragraph between the lists means the author ended one", { skip }, () => {
  // Not a continuation — the tidy-up is right to fire here.
  const r = afterLeaving(
    `<ul><li>one</li>${source("- ")}</ul><p>text</p><ul><li>three</li></ul>`,
    1
  );

  assert.equal(r.kept, false);
});

test("hybrid: the last list on the page still tidies its trailing blank row", { skip }, () => {
  const r = afterLeaving(`<ul><li>one</li>${source("- ")}</ul>`, 1);

  assert.equal(r.kept, false);
});

test("an adjacent list is reported as the next item", { skip }, () => {
  const e = editor(`<ul><li>one</li><li>two</li></ul><ul><li>three</li></ul>`, "hybrid");
  const last = items(e)[1];

  const next = e._nextListSibling(last);

  assert.ok(next, "the following list's first item should be found");
  assert.equal(next.textContent, "three");
  e.cleanup();
});


// --------------------------------------------------------------------------
// Ordered lists that do not start at 1, in hybrid mode.
// --------------------------------------------------------------------------

function renumberFirst(html, typed) {
  const e = editor(html, "hybrid");
  const first = items(e)[0];

  first.setAttribute("data-leaf-source", "li");
  first.textContent = typed;
  e._renderListItemFromSource = (src) => {
    const li = document.createElement("li");
    const body = src.replace(/^(- |\d+\. )/, "");
    if (body) li.appendChild(document.createTextNode(body));
    return li;
  };
  e._renderBlockFromSource = () => document.createElement("p");
  e._exitListItemToParagraph = () => {};

  e._exitSourceMode(first);

  const start = e._visualEl.querySelector("ol").getAttribute("start");
  e.cleanup();
  return start;
}

test("hybrid: the revealed marker shows the number the item displays", { skip }, () => {
  // It used to reveal `1. ` for the first item of an `<ol start="19">`, which
  // both lied about the item and renumbered the list once serialized.
  const e = editor('<ol start="19"><li>nineteen</li><li>twenty</li></ol>', "hybrid");
  const first = items(e)[0];

  caretAtEndOf(first);
  const src = e._enterSourceMode(first);

  assert.match(src.textContent, /^19\. /);
  e.cleanup();
});

test("hybrid: Enter continues from the displayed number", { skip }, () => {
  const e = editor('<ol start="19"><li>nineteen</li><li>twenty</li></ol>', "hybrid");
  const first = items(e)[0];

  caretAtEndOf(first);
  e._sourceBlock = e._enterSourceMode(first);
  caretAtEndOf(e._sourceBlock);
  e._maybeHandleSourceEnter();

  assert.match(e._visualEl.innerHTML, /20\. /, readable(e._visualEl));
  e.cleanup();
});

test("hybrid: editing the first item's number renumbers the list", { skip }, () => {
  // The only place a hand-typed number can live: CommonMark takes the start
  // from the first item, and the attribute belongs to the <ol>. Without this
  // the number was stripped with the marker and the list snapped back.
  assert.equal(renumberFirst("<ol><li>a</li><li>b</li></ol>", "19. a"), "19");
});

test("hybrid: renumbering the first item back to 1 drops the attribute", { skip }, () => {
  assert.equal(renumberFirst('<ol start="19"><li>a</li></ol>', "1. a"), null);
});
