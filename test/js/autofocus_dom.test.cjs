"use strict";

// `autofocus`: an editor opened to be typed into gets the caret straight away,
// at the end of what is there.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function editorWith(html, mode = "hybrid") {
  const e = dom.editor(html, mode);
  e._visualEl.setAttribute("tabindex", "0");
  // The frame the real method waits for, run at once.
  global.requestAnimationFrame = (fn) => fn();
  return e;
}

test("the caret goes to the end of the text", { skip: dom.skip }, () => {
  const e = editorWith("<p>first</p><p>last line</p>");
  Object.getPrototypeOf(e)._autofocus.call(e);

  assert.equal(document.activeElement, e._visualEl);
  const sel = window.getSelection();
  assert.ok(sel.isCollapsed);
  const last = e._visualEl.lastElementChild;
  assert.ok(last.contains(sel.anchorNode) || sel.anchorNode === last);
  assert.equal(sel.anchorOffset, sel.anchorNode.childNodes.length || sel.anchorNode.length);
  e.cleanup();
});

test("an empty note gets the caret too", { skip: dom.skip }, () => {
  const e = editorWith("<p><br></p>");
  Object.getPrototypeOf(e)._autofocus.call(e);
  assert.equal(document.activeElement, e._visualEl);
  assert.equal(window.getSelection().rangeCount, 1);
  e.cleanup();
});

test("a readonly editor is left alone", { skip: dom.skip }, () => {
  const e = editorWith("<p>x</p>");
  e._readonly = true;
  document.body.focus();
  Object.getPrototypeOf(e)._autofocus.call(e);
  assert.notEqual(document.activeElement, e._visualEl);
  e.cleanup();
});

test("markdown mode focuses the textarea, caret at the end", { skip: dom.skip }, () => {
  const e = editorWith("<p>x</p>", "markdown");
  const ta = document.createElement("textarea");
  ta.value = "# Title\n\nbody";
  document.body.appendChild(ta);
  e._getMarkdownTextarea = () => ta;

  Object.getPrototypeOf(e)._autofocus.call(e);
  assert.equal(document.activeElement, ta);
  assert.equal(ta.selectionStart, ta.value.length);
  ta.remove();
  e.cleanup();
});
