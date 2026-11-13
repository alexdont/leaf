"use strict";

// ALEX-133: `action: :focus` / `el.leafFocus({at})` put the caret inside the
// last (first) block's text, never after the block.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function ed(html, mode = "hybrid") {
  const e = dom.editor(html, mode);
  e._visualEl.setAttribute("tabindex", "0");
  e._updateSourceBlock = () => {};
  return e;
}

test("end: inside the last text, so typing stays in the paragraph", { skip: dom.skip }, () => {
  const e = ed("<p>Laev:&nbsp;</p>");
  assert.equal(e._focusAt("end"), true);
  assert.equal(document.activeElement, e._visualEl);
  const sel = window.getSelection();
  assert.equal(sel.anchorNode, e._visualEl.firstChild.firstChild, "the text node, not the editor");
  assert.equal(sel.anchorOffset, 6);
  e.cleanup();
});

test("end of a nested list: the deepest last item's text", { skip: dom.skip }, () => {
  const e = ed("<ul><li>a<ul><li>b</li></ul></li></ul>");
  e._focusAt("end");
  const sel = window.getSelection();
  assert.equal(sel.anchorNode.textContent, "b");
  assert.equal(sel.anchorOffset, 1);
  e.cleanup();
});

test("start: the first block's first character", { skip: dom.skip }, () => {
  const e = ed("<p>one</p><p>two</p>");
  e._focusAt("start");
  const sel = window.getSelection();
  assert.equal(sel.anchorNode.textContent, "one");
  assert.equal(sel.anchorOffset, 0);
  e.cleanup();
});

test("an empty editor gets a paragraph to type into", { skip: dom.skip }, () => {
  const e = ed("");
  e._focusAt();
  assert.equal(e._visualEl.innerHTML, "<p><br></p>");
  assert.equal(window.getSelection().anchorNode, e._visualEl.firstChild);
  e.cleanup();
});

test("markdown mode: the textarea, at the end or the start", { skip: dom.skip }, () => {
  const e = ed("<p>x</p>", "markdown");
  const ta = document.createElement("textarea");
  ta.value = "# Title\nbody";
  document.body.appendChild(ta);
  e._getMarkdownTextarea = () => ta;
  e._focusAt("end");
  assert.equal(document.activeElement, ta);
  assert.equal(ta.selectionStart, ta.value.length);
  e._focusAt("start");
  assert.equal(ta.selectionStart, 0);
  ta.remove();
  e.cleanup();
});

test("readonly: no focus", { skip: dom.skip }, () => {
  const e = ed("<p>x</p>");
  e._readonly = true;
  document.body.focus();
  assert.equal(e._focusAt("end"), false);
  assert.notEqual(document.activeElement, e._visualEl);
  e.cleanup();
});
