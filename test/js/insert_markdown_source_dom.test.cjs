"use strict";

// `insert_markdown` inserts MARKDOWN. In hybrid mode the caret's block has to
// be in source form when the text lands; a block that has not switched yet
// (the host's button took the focus, the editor is focused and written to in
// one go) took it as rendered content, and the switch escaped it: a host
// inserting `[[A]] x` got `\[\[A]] x`, a dead link.
//
// The same holds for any text inserted before `selectionchange` has run, so
// the `beforeinput` handler switches the block first too.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function hybridEditor(html) {
  const e = dom.editor(html, "hybrid");
  const proto = Object.getPrototypeOf(e);
  e._updateSourceBlock = proto._updateSourceBlock;
  e._refreshSourceBlock = proto._refreshSourceBlock;
  e._visualEl.focus = () => {};
  e._wikiLinks = true;
  return e;
}

function caret(node, offset) {
  const range = document.createRange();
  range.setStart(node, offset);
  range.collapse(true);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(range);
}

// What `insertText` does: the text goes in at the caret.
function insertTextAtCaret(text) {
  const range = window.getSelection().getRangeAt(0);
  const node = document.createTextNode(text);
  range.insertNode(node);
  range.setStartAfter(node);
  range.collapse(true);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(range);
  return true;
}

test("insert_markdown into a block not yet in source form keeps the markdown", { skip: dom.skip }, () => {
  const e = hybridEditor("<p><br></p>");
  caret(e._visualEl.firstChild, 0);
  document.execCommand = (cmd, _ui, value) => cmd === "insertText" && insertTextAtCaret(value);

  e._handleCommand({ action: "insert_markdown", text: "[[A]] x" });

  assert.equal(e._currentMarkdown().trim(), "[[A]] x");
  e.cleanup();
});

test("insert_markdown in visual mode is unchanged (no source form there)", { skip: dom.skip }, () => {
  const e = hybridEditor("<p><br></p>");
  e._mode = "visual";
  caret(e._visualEl.firstChild, 0);
  document.execCommand = (cmd, _ui, value) => cmd === "insertText" && insertTextAtCaret(value);

  e._handleCommand({ action: "insert_markdown", text: "plain words" });

  assert.equal(e._currentMarkdown().trim(), "plain words");
  e.cleanup();
});

test("_ensureSourceBlock leaves a block that is already the source block alone", { skip: dom.skip }, () => {
  const e = hybridEditor('<p data-leaf-source="p">x</p>');
  e._sourceBlock = e._visualEl.firstChild;
  caret(e._sourceBlock.firstChild, 1);
  let calls = 0;
  e._updateSourceBlock = () => calls++;

  e._ensureSourceBlock();
  assert.equal(calls, 0);
  e.cleanup();
});

test("a beforeinput into a block not yet in source form switches it first", { skip: dom.skip }, () => {
  const e = hybridEditor("<p><br></p>");
  Object.getPrototypeOf(e)._setupCommandWindow.call(e);
  caret(e._visualEl.firstChild, 0);

  e._visualEl.dispatchEvent(
    new window.InputEvent("beforeinput", { inputType: "insertText", data: "[", bubbles: true, cancelable: true })
  );

  const block = e._visualEl.firstChild;
  assert.ok(block.hasAttribute("data-leaf-source"), "the block is in source form before the text lands");
  assert.equal(e._sourceBlock, block);
  e.cleanup();
});
