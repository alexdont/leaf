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


// --------------------------------------------------------------------------
// Task lists from the toolbar.
//
// Clicking the button appeared to do nothing unless text was selected first.
// The item WAS created — and then removed the moment the caret left it, by the
// same tidy-up that clears an abandoned trailing bullet. An empty checkbox is
// not abandoned residue: it renders as a tickable box, and it is exactly what
// the button is for.
// --------------------------------------------------------------------------

function taskEditor(html) {
  const e = editor(html, "hybrid");

  e._insertBlockAfterCurrent = (node) => e._visualEl.appendChild(node);
  e._placeCaretIn = (n) => {
    try {
      caretAtEndOf(n);
    } catch (_) {
      /* nothing to place in an empty node */
    }
  };

  return e;
}

test("the toolbar button on an empty line makes a checkbox with somewhere to type", { skip }, () => {
  const e = taskEditor("<p><br></p>");
  const block = e._visualEl.children[0];

  e._getCurrentBlock = () => block;
  e._insertTaskList();

  const li = e._visualEl.querySelector("li.leaf-task");

  assert.ok(li, "the button should create a task item");
  assert.ok(li.querySelector(".leaf-task-box"), "it needs its checkbox");
  e.cleanup();
});

test("a checkbox created on an empty line survives the caret leaving", { skip }, () => {
  // The reported symptom: it looked as though nothing was created at all.
  const e = taskEditor("<p><br></p><p>after</p>");
  const block = e._visualEl.children[0];

  e._getCurrentBlock = () => block;
  e._insertTaskList();

  const li = e._visualEl.querySelector("li.leaf-task");
  caretAtEndOf(li);
  e._sourceBlock = e._enterSourceMode(li);
  e._exitSourceMode(e._sourceBlock);

  const after = e._visualEl.querySelector("li.leaf-task");

  assert.ok(after, "the checkbox must not be tidied away");
  assert.ok(after.querySelector(".leaf-task-box"), "and its box must be rebuilt");
  e.cleanup();
});

const taskLi = (text) =>
  `<li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>${text}</li>`;

test("Enter on a task item continues the checklist", { skip }, () => {
  const e = taskEditor(`<ul>${taskLi("buy milk")}</ul>`);
  const li = items(e)[0];

  caretAtEndOf(li);
  e._sourceBlock = e._enterSourceMode(li);
  caretAtEndOf(e._sourceBlock);
  e._maybeHandleSourceEnter();

  assert.equal(items(e).length, 2);
  assert.match(items(e)[1].textContent, /^- \[ \] /, "the new item carries a fresh unchecked box");
  e.cleanup();
});

test("Enter on the last, empty task item finishes the checklist", { skip }, () => {
  // The way out of a checklist, and the behaviour asked for: keep pressing
  // Enter to add boxes, press it on an empty one to stop.
  const e = taskEditor(`<ul>${taskLi("done")}${taskLi(ZWSP)}</ul>`);
  const li = items(e)[1];

  caretAtEndOf(li);
  e._sourceBlock = e._enterSourceMode(li);
  caretAtEndOf(e._sourceBlock);
  e._maybeHandleSourceEnter();

  assert.equal(items(e).length, 1);
  assert.match(e._visualEl.innerHTML, /<p>/, "and lands in a paragraph below the list");
  e.cleanup();
});

// ---------------------------------------------------------------------------
// The bullet and numbered list buttons on nothing
// ---------------------------------------------------------------------------
//
// execCommand("insert*List") needs a caret on content: on an empty line or a
// fresh editor it did nothing, so the buttons could not START a list — the
// same complaint the task-list button drew, fixed the same way.

function listEditor(html) {
  const e = editor(html, "hybrid");

  e._insertBlockAfterCurrent = (node) => e._visualEl.appendChild(node);
  e._placeCaretIn = (n) => {
    try {
      caretAtEndOf(n);
    } catch (_) {
      /* nothing to place in an empty node */
    }
  };

  return e;
}

test("the bullet button on an empty line starts a list you can type into", { skip }, () => {
  const e = listEditor("<p><br></p>");
  const block = e._visualEl.children[0];
  e._getCurrentBlock = () => block;

  assert.equal(e._insertList("ul"), true, "the button must handle this itself");

  const li = e._visualEl.querySelector("ul > li");
  assert.ok(li, "an empty item to start the list from");
  assert.equal(e._visualEl.querySelector("p"), null, "the empty line became the list");

  e.cleanup();
});

test("the numbered button does the same with an ol", { skip }, () => {
  const e = listEditor("<p><br></p>");
  const block = e._visualEl.children[0];
  e._getCurrentBlock = () => block;

  assert.equal(e._insertList("ol"), true);
  assert.ok(e._visualEl.querySelector("ol > li"), "a numbered list, not a bulleted one");

  e.cleanup();
});

test("an editor nobody has clicked into still gets its list", { skip }, () => {
  const e = listEditor("<p>existing</p>");
  e._getCurrentBlock = () => null;

  assert.equal(e._insertList("ul"), true);
  assert.ok(e._visualEl.querySelector("ul > li"), "appended, since there is no current line");
  assert.ok(e._visualEl.querySelector("p"), "and the existing text is untouched");

  e.cleanup();
});

test("a line with text on it converts rather than splits", { skip }, () => {
  const e = listEditor("<p>groceries</p>");
  const block = e._visualEl.children[0];
  e._getCurrentBlock = () => block;

  assert.equal(e._insertList("ul"), true);

  const li = e._visualEl.querySelector("ul > li");
  assert.equal(li.textContent, "groceries", "the line's text becomes the first item");
  assert.equal(e._visualEl.querySelector("p"), null);

  e.cleanup();
});

test("with the caret already in a list, the native command keeps the job", { skip }, () => {
  const e = listEditor("<ul><li>item</li></ul>");
  const li = e._visualEl.querySelector("li");
  e._getCurrentBlock = () => li;

  assert.equal(e._insertList("ul"), false, "toggling out of a list is execCommand's case");
  assert.equal(e._visualEl.querySelectorAll("ul").length, 1, "and nothing was built");

  e.cleanup();
});

test("with text selected, the native command keeps the job", { skip }, () => {
  const e = listEditor("<p>one</p><p>two</p>");
  const range = document.createRange();
  range.setStart(e._visualEl.children[0].firstChild, 0);
  range.setEnd(e._visualEl.children[1].firstChild, 3);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  assert.equal(e._insertList("ul"), false, "multi-line conversion is execCommand's case");
  assert.equal(e._visualEl.querySelector("ul"), null);

  e.cleanup();
});

test("the empty item is one the empty-line rules will not tidy away", { skip }, () => {
  // The task-list lesson's second half: creating it is nothing if hybrid's
  // cleanup deletes it the moment the caret leaves.
  const e = listEditor("<p><br></p><p>after</p>");
  const block = e._visualEl.children[0];
  e._getCurrentBlock = () => block;

  e._insertList("ul");

  const li = e._visualEl.querySelector("ul > li");
  caretAtEndOf(li);
  e._sourceBlock = e._enterSourceMode(li);
  e._exitSourceMode(e._sourceBlock);

  assert.ok(e._visualEl.querySelector("ul > li"), "the empty item must survive the caret leaving");

  e.cleanup();
});

test("the toolbar arms actually route through _insertList", { skip }, () => {
  // jsdom cannot run execCommand, so no behavioural test reaches the case
  // arms — and a fix that exists but is never called is the bug back again.
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  for (const [action, tag] of [["bulletList", "ul"], ["orderedList", "ol"]]) {
    const arm = src.slice(src.indexOf(`case "${action}":`));
    const insertAt = arm.indexOf(`_insertList("${tag}")`);
    const execAt = arm.indexOf("document.execCommand");

    assert.ok(insertAt >= 0, `${action} must try _insertList`);
    assert.ok(insertAt < execAt, `${action} must try it BEFORE falling back to execCommand`);
  }
});
