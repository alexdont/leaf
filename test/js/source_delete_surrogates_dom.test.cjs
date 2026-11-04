"use strict";

// Backspace and Delete in a hybrid source block edit the block's source
// string one unit at a time. An emoji is two units; removing one leaves half
// a character, which JSON cannot carry — the push was refused and the edit
// lost.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function sourceEditor(text, caret) {
  const e = dom.editor('<p data-leaf-source="p">' + text + "</p>", "hybrid");
  const proto = Object.getPrototypeOf(e);
  e._maybeHandleSourceDelete = proto._maybeHandleSourceDelete;
  e._refreshSourceBlock = proto._refreshSourceBlock;
  e._sourceBlock = e._visualEl.firstChild;

  const node = e._sourceBlock.firstChild;
  const range = document.createRange();
  range.setStart(node, caret);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  return e;
}

test("Backspace after an emoji removes the whole emoji", { skip: dom.skip }, () => {
  const e = sourceEditor("ab\u{1F600}", 4);
  assert.equal(e._maybeHandleSourceDelete(true, false), true);
  assert.equal(e._sourceBlock.textContent, "ab");
  assert.ok(e._sourceBlock.textContent.isWellFormed());
  e.cleanup();
});

test("Delete before an emoji removes the whole emoji", { skip: dom.skip }, () => {
  const e = sourceEditor("ab\u{1F600}c", 2);
  assert.equal(e._maybeHandleSourceDelete(false, false), true);
  assert.equal(e._sourceBlock.textContent, "abc");
  e.cleanup();
});

test("plain characters still go one at a time", { skip: dom.skip }, () => {
  const back = sourceEditor("abc", 3);
  assert.equal(back._maybeHandleSourceDelete(true, false), true);
  assert.equal(back._sourceBlock.textContent, "ab");
  back.cleanup();

  const fwd = sourceEditor("abc", 1);
  assert.equal(fwd._maybeHandleSourceDelete(false, false), true);
  assert.equal(fwd._sourceBlock.textContent, "ac");
  fwd.cleanup();
});
