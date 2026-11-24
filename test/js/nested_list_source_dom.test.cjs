"use strict";

// Arrowing up into a list item that has a nested list must keep the nested
// list. Hybrid mode turns the item the caret enters into its markdown source;
// it used to serialize the WHOLE item — nested list included — into that one
// line and drop the nested list's elements with the old item, so the nested
// items came back glued onto the parent's line, and saved that way.
//
// Now the nested lists are lifted out to sit right after the source item
// (drawn indented, serialized as nested under it), and put back inside the
// rendered item when the caret leaves.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert/strict");
const dom = require("./support/dom.cjs");

const skip = dom.skip;
const HTML =
  "<ul><li>Leaf</li><li>Polish:<ul><li>Viewer</li><li>Boards</li></ul></li></ul>";

function caretAtEndOf(el) {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  let last = null;
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!el.querySelector("ul, ol") || !n.parentElement.closest("li li")) last = n;
  }
  const r = document.createRange();
  if (last) r.setStart(last, last.length);
  else r.setStart(el, 0);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
}

function parent(e) {
  return e._visualEl.querySelectorAll(":scope > ul > li")[1];
}

test("entering a parent item shows only its own line as source", { skip }, () => {
  const e = dom.editor(HTML, "hybrid");
  const li = parent(e);
  caretAtEndOf(li);
  const src = e._enterSourceMode(li);

  assert.equal(src.textContent.replace(/​/g, ""), "- Polish:", "no nested text on the line");
  const lifted = src.nextElementSibling;
  assert.equal(lifted && lifted.tagName, "UL", "the nested list follows the item");
  assert.ok(lifted.hasAttribute("data-leaf-lifted"));
  assert.equal(lifted.querySelectorAll("li").length, 2, "nested items intact");
  e.cleanup();
});

test("while the parent is in source form, the markdown keeps the nesting", { skip }, () => {
  const e = dom.editor(HTML, "hybrid");
  const li = parent(e);
  caretAtEndOf(li);
  e._enterSourceMode(li);

  const md = e._currentMarkdown();
  assert.match(md, /- Polish:\n  - Viewer\n  - Boards/, md);
  e.cleanup();
});

test("leaving the parent puts its nested list back inside it", { skip }, () => {
  const e = dom.editor(HTML, "hybrid");
  const li = parent(e);
  caretAtEndOf(li);
  const src = e._enterSourceMode(li);
  e._exitSourceMode(src);

  const back = parent(e);
  assert.equal(back.firstChild.textContent, "Polish:");
  const nested = back.querySelector(":scope > ul");
  assert.ok(nested, "nested list inside the item again");
  assert.equal(nested.hasAttribute("data-leaf-lifted"), false);
  assert.equal(nested.querySelectorAll("li").length, 2);
  assert.equal(e._visualEl.querySelectorAll(":scope > ul > ul").length, 0, "nothing left outside");
  assert.match(e._currentMarkdown(), /- Polish:\n  - Viewer\n  - Boards/);
  e.cleanup();
});

test("the caret stays in the nested item it moved to", { skip }, () => {
  const e = dom.editor(HTML, "hybrid");
  const li = parent(e);
  caretAtEndOf(li);
  const src = e._enterSourceMode(li);

  // ArrowDown: the caret is now in a nested item when the parent exits.
  const viewer = src.nextElementSibling.querySelector("li").firstChild;
  const r = document.createRange();
  r.setStart(viewer, 3);
  r.collapse(true);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(r);
  e._exitSourceMode(src);

  const sel = window.getSelection();
  assert.equal(sel.anchorNode, viewer, "same text node");
  assert.equal(sel.anchorOffset, 3);
  assert.ok(parent(e).contains(viewer), "now inside the item again");
  e.cleanup();
});
