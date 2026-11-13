"use strict";

// Shift+Enter inside a hybrid source block puts a "\n" in the block's text
// with the caret after it. It used to insert a <br> that the refresh turned
// into "\n" with the caret left in front, so "one", Shift+Enter, "two" came
// out as "onetwo\n".
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function sourceEditor(inner) {
  const e = dom.editor(`<p data-leaf-source="p">${inner}</p>`, "hybrid");
  e._sourceBlock = e._visualEl.firstChild;
  e._getCurrentBlock = () => e._sourceBlock;
  e._updateSourceBlock = () => {};
  return e;
}

function shiftEnter(e) {
  const ev = new window.KeyboardEvent("keydown", { key: "Enter", shiftKey: true, bubbles: true, cancelable: true });
  e._onVisualKeydown(ev);
  return ev;
}

function caretAt(node, offset) {
  const r = document.createRange();
  r.setStart(node, offset);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
}

test("a break in the middle splits the text at the caret", { skip: dom.skip }, () => {
  const e = sourceEditor("onetwo");
  caretAt(e._sourceBlock.firstChild, 3);
  assert.ok(shiftEnter(e).defaultPrevented);

  assert.equal(e._sourceBlock.textContent, "one\ntwo");
  assert.equal(e._sourceBlock.querySelector("br"), null, "no <br> in source text");
  const sel = window.getSelection();
  const before = document.createRange();
  before.selectNodeContents(e._sourceBlock);
  before.setEnd(sel.anchorNode, sel.anchorOffset);
  assert.equal(before.toString(), "one\n", "caret after the break");
  e.cleanup();
});

test("a break at the end gets a filler line for the caret", { skip: dom.skip }, () => {
  const e = sourceEditor("one");
  caretAt(e._sourceBlock.firstChild, 3);
  shiftEnter(e);

  assert.equal(e._sourceBlock.textContent, "one\n");
  const filler = e._sourceBlock.lastChild;
  assert.equal(filler.tagName, "BR");
  assert.ok(filler.hasAttribute("data-leaf-filler"));
  const sel = window.getSelection();
  assert.equal(sel.anchorNode.nodeType, 3);
  assert.equal(sel.anchorOffset, sel.anchorNode.textContent.length, "caret after the newline, before the filler");
  e.cleanup();
});

test("an empty block loses its placeholder <br>, so there is one break, not two", { skip: dom.skip }, () => {
  const e = sourceEditor("<br>");
  caretAt(e._sourceBlock, 0);
  shiftEnter(e);

  assert.equal(e._sourceBlock.textContent, "\n");
  const brs = [...e._sourceBlock.querySelectorAll("br")];
  assert.equal(brs.length, 1);
  assert.ok(brs[0].hasAttribute("data-leaf-filler"));
  e.cleanup();
});

test("a rendered (non-source) block still gets a <br>", { skip: dom.skip }, () => {
  const e = dom.editor("<p>one</p>", "visual");
  dom.caretAtEndOf(e._visualEl.firstChild);
  e._getCurrentBlock = () => e._visualEl.firstChild;
  shiftEnter(e);
  assert.ok(e._visualEl.firstChild.querySelector("br"));
  e.cleanup();
});
