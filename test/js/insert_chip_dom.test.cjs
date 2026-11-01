"use strict";

// A tag inserted from the host (`send_update(Leaf, action: :insert_markdown)`,
// a toolbar button) is placed by Leaf itself, from the block the caret is in.
//
// It used to go through `execCommand("insertHTML")`, whose result depends on
// where the caret is. Inside a line showing its source, or an empty line, the
// chip was serialised as its visible text ("HeadlineDouble-click to
// editHeadline text…" was saved into the post); mid-line it split the
// paragraph; next to another chip it did nothing.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

const CHIP =
  '<span class="leaf-atomic leaf-atomic-block" contenteditable="false" data-leaf-tag="Headline" data-leaf-raw="&lt;Headline&gt;Hi&lt;/Headline&gt;">Headline</span>';
const INLINE =
  '<span class="leaf-atomic leaf-atomic-inline" contenteditable="false" data-leaf-tag="Note" data-leaf-raw="&lt;Note&gt;x&lt;/Note&gt;">Note</span>';

function editor(html, mode = "hybrid") {
  const e = dom.editor(html, mode);
  // A real browser keeps the caret when an editor that has it is focused;
  // jsdom's focus() moves it, which is not what is under test.
  e._visualEl.focus = () => {};
  e._preserveTags = ["headline", "note"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};
  e._refreshSourceBlock = () => {};
  return e;
}

function caret(node, offset) {
  const range = document.createRange();
  range.setStart(node, offset);
  range.collapse(true);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(range);
}

function run(e, payload) {
  const calls = [];
  document.execCommand = (cmd, _ui, value) => {
    calls.push([cmd, value]);
    return true;
  };
  e._handleCommand(payload);
  return calls;
}

const block = (chip = CHIP) => ({ action: "insert_markdown", text: "\n<Headline>Hi</Headline>\n", chip });

const shape = (e) =>
  [...e._visualEl.children].map((c) =>
    c.querySelector("[data-leaf-tag]") ? "CHIP" : c.textContent === "" ? "EMPTY" : c.textContent
  );

test("a block goes after the line the caret is on, never into it", { skip: dom.skip }, () => {
  for (const offset of [0, 2, 5]) {
    const e = editor("<p>hello</p><p>tail</p>");
    caret(e._visualEl.children[0].firstChild, offset);

    const calls = run(e, block());

    assert.deepEqual(shape(e), ["hello", "CHIP", "tail"], `caret at ${offset}`);
    assert.deepEqual(calls, [], "the browser's insertHTML is not involved");
    e.cleanup();
  }
});

test("a line with just a space is a line with content", { skip: dom.skip }, () => {
  const e = editor("<p>a</p><p> </p><p>z</p>");
  caret(e._visualEl.children[1].firstChild, 1);

  run(e, block());

  // A space is blank: the block takes its place rather than leaving a
  // stray empty line above it.
  assert.deepEqual(shape(e), ["a", "CHIP", "z"]);
  e.cleanup();
});

test("an empty line is replaced by the block", { skip: dom.skip }, () => {
  const e = editor("<p>a</p><p><br></p><p>z</p>");
  caret(e._visualEl.children[1], 0);

  run(e, block());

  assert.deepEqual(shape(e), ["a", "CHIP", "z"]);
  e.cleanup();
});

test("an active source line is left whole and the block follows it", { skip: dom.skip }, () => {
  const e = editor('<p data-leaf-source="p">abc def</p><p>z</p>');
  e._sourceBlock = e._visualEl.children[0];
  caret(e._visualEl.children[0].firstChild, 3);

  run(e, block());

  assert.deepEqual(shape(e), ["abc def", "CHIP", "z"]);
  e.cleanup();
});

test("a block gets a line after it to keep typing in", { skip: dom.skip }, () => {
  const e = editor("<p>only</p>");
  caret(e._visualEl.children[0].firstChild, 4);

  run(e, block());

  assert.deepEqual(shape(e), ["only", "CHIP", "EMPTY"]);
  assert.equal(window.getSelection().anchorNode, e._visualEl.children[2]);
  e.cleanup();
});

test("next to another block the new one still lands", { skip: dom.skip }, () => {
  const e = editor(`<p>one</p><p>${CHIP}</p>`);
  caret(e._visualEl.children[1], 0);

  run(e, block());

  assert.deepEqual(shape(e), ["one", "CHIP", "CHIP", "EMPTY"]);
  e.cleanup();
});

test("with no caret in the editor it goes to the end", { skip: dom.skip }, () => {
  const e = editor("<p>one</p>");
  window.getSelection().removeAllRanges();

  run(e, block());

  assert.deepEqual(shape(e), ["one", "CHIP", "EMPTY"]);
  e.cleanup();
});

test("the browser's own chip is used when the server sent none", { skip: dom.skip }, () => {
  const e = editor("<p>one</p>");
  caret(e._visualEl.children[0].firstChild, 3);

  run(e, { action: "insert_markdown", text: '<Headline stretch="30">Hi</Headline>' });

  assert.deepEqual(shape(e), ["one", "CHIP", "EMPTY"]);
  assert.match(e._visualEl.innerHTML, /data-leaf-tag="Headline"/);
  e.cleanup();
});

test("an inline tag goes in at the caret, replacing a selection", { skip: dom.skip }, () => {
  const e = editor("<p>say hello now</p>", "visual");
  const text = e._visualEl.children[0].firstChild;
  const range = document.createRange();
  range.setStart(text, 4);
  range.setEnd(text, 9);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(range);

  run(e, { action: "insert_markdown", text: "<Note>x</Note>", chip: INLINE, layout: "inline", raw: "<Note>x</Note>" });

  const p = e._visualEl.children[0];
  assert.equal(p.querySelectorAll("[data-leaf-tag='Note']").length, 1);
  assert.equal(p.firstChild.textContent, "say ");
  assert.equal(p.lastChild.textContent, " now");
  e.cleanup();
});

test("on a source line an inline tag goes in as source text", { skip: dom.skip }, () => {
  const e = editor('<p data-leaf-source="p">say hello</p>');
  e._sourceBlock = e._visualEl.children[0];
  caret(e._visualEl.children[0].firstChild, 4);

  const calls = run(e, {
    action: "insert_markdown",
    text: "<Note>x</Note>",
    chip: INLINE,
    layout: "inline",
    raw: "<Note>x</Note>",
  });

  // The line is showing its markdown; the tag is text there, and becomes a
  // chip when the caret leaves, like one typed by hand.
  assert.deepEqual(calls, [["insertText", "<Note>x</Note>"]]);
  assert.equal(e._visualEl.querySelectorAll("[data-leaf-tag]").length, 0);
  e.cleanup();
});

test("plain text is inserted as text", { skip: dom.skip }, () => {
  const e = editor("<p>x</p>", "visual");

  const calls = run(e, { action: "insert_markdown", text: "hello" });

  assert.deepEqual(calls, [["insertText", "hello"]]);
  e.cleanup();
});
