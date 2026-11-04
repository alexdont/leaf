"use strict";

// Enter inside bold, italic or a link divides the paragraph where the
// caret is. It used to open an empty paragraph below and leave the whole
// line, caret and all, behind.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");
const { skip, editor, pressEnter } = dom;

function live(html) {
  const e = editor(html, "visual");
  const proto = Object.getPrototypeOf(e);
  e._inlineFormattingAncestor = proto._inlineFormattingAncestor;
  e._getCurrentBlock = () => e._visualEl.firstChild;
  return e;
}

function caretIn(node, offset) {
  const range = document.createRange();
  range.setStart(node, offset);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}

test("Enter in the middle of a bold run splits the paragraph there", { skip }, () => {
  const e = live("<p>Hello <strong>world</strong> bye</p>");
  caretIn(e._visualEl.querySelector("strong").firstChild, 3);

  const evt = pressEnter(e);

  assert.equal(evt.defaultPrevented, true);
  assert.equal(e._visualEl.innerHTML, "<p>Hello <strong>wor</strong></p><p><strong>ld</strong> bye</p>");
  const sel = window.getSelection();
  assert.equal(sel.anchorNode.textContent, "ld");
  assert.equal(sel.anchorOffset, 0);
  e.cleanup();
});

test("Enter at the end of a bold run opens a plain paragraph", { skip }, () => {
  const e = live("<p>a <strong>b</strong></p>");
  caretIn(e._visualEl.querySelector("strong").firstChild, 1);

  pressEnter(e);

  assert.equal(e._visualEl.innerHTML, "<p>a <strong>b</strong></p><p><br></p>");
  e.cleanup();
});

test("Enter inside a link keeps the link's halves linked", { skip }, () => {
  const e = live('<p>see <a href="/x">docs here</a> now</p>');
  caretIn(e._visualEl.querySelector("a").firstChild, 4);

  pressEnter(e);

  assert.equal(
    e._visualEl.innerHTML,
    '<p>see <a href="/x">docs</a></p><p><a href="/x"> here</a> now</p>'
  );
  e.cleanup();
});

test("in a list item the new block is an item", { skip }, () => {
  const e = live("<ul><li>a <em>bc</em> d</li></ul>");
  e._getCurrentBlock = () => e._visualEl.querySelector("li");
  caretIn(e._visualEl.querySelector("em").firstChild, 1);

  pressEnter(e);

  assert.equal(e._visualEl.innerHTML, "<ul><li>a <em>b</em></li><li><em>c</em> d</li></ul>");
  e.cleanup();
});
