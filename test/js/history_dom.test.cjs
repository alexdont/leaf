"use strict";

// Undo-history behaviour that needs a real DOM.
//
// Its companion `history.test.cjs` covers the stack as pure state with the DOM
// stubbed. That cannot reach the parts that measure a caret — which is where
// the worst defect in this feature lived.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

test("measuring a caret on an element does not recurse", { skip }, () => {
  // The caret sits ON an element, not in text, for any empty block. The first
  // version of `_historyTextOffset` walked text nodes and, failing to find such
  // a container, called ITSELF with the same element — unconditional infinite
  // recursion.
  //
  // It threw "too much recursion" out of the capture that runs before every
  // toolbar action, so on an empty row the action never ran at all: clicking
  // Task List did nothing, while the same click on a row with text worked,
  // because a caret in text returned before reaching that branch.
  const e = editor("<p>hello</p><p><br></p>");
  const empty = e._visualEl.children[1];

  // A throw is the regression; the value only has to be sane.
  const offset = e._historyTextOffset(empty, 0);

  assert.equal(typeof offset, "number");
  assert.ok(offset >= 0);
  e.cleanup();
});

test("a caret in text measures the characters before it", { skip }, () => {
  const e = editor("<p>hello</p>");

  assert.equal(e._historyTextOffset(e._visualEl.children[0].firstChild, 3), 3);
  e.cleanup();
});

test("a caret outside the editor measures zero rather than throwing", { skip }, () => {
  const e = editor("<p>hello</p>");

  assert.equal(e._historyTextOffset(document.createElement("div"), 0), 0);
  assert.equal(e._historyTextOffset(null, 0), 0);
  e.cleanup();
});

test("capturing on an empty row works end to end", { skip }, () => {
  // The failing path in full: a caret on an empty block, then the capture that
  // every toolbar action runs first.
  const e = editor("<p>hello</p><p><br></p>");

  delete e._historyCapture;
  delete e._historyCaptureNow;

  const empty = e._visualEl.children[1];
  const range = document.createRange();
  range.setStart(empty, 0);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  e._historyInit();

  assert.ok(e._history.length >= 1, "the opening state should be captured");
  e.cleanup();
});

test("the toolbar reaches its action from an empty row", { skip }, () => {
  // What the user saw: the click did nothing, because the capture in front of
  // it threw before the action ran.
  const e = editor("<p><br></p>", "hybrid");

  delete e._historyCapture;
  delete e._historyCaptureNow;
  e._historyInit();

  const block = e._visualEl.children[0];
  e._getCurrentBlock = () => block;
  e._placeCaretIn = () => {};
  e._insertBlockAfterCurrent = (node) => e._visualEl.appendChild(node);

  e._execToolbarAction("taskList");

  assert.ok(
    e._visualEl.querySelector("li.leaf-task"),
    "clicking Task List on an empty row must create a checkbox"
  );
  e.cleanup();
});
