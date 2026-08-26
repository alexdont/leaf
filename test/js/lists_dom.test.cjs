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
