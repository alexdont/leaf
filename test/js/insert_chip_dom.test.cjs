"use strict";

// A tag inserted from the host (`send_update(Leaf, action: :insert_markdown)`)
// arrives with the finished chip when the server could draw one. The browser
// can only draw an approximation (no markdown renderer, and no way to turn a
// `file_uuid` into a picture), so the server's wins.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function run(e, payload) {
  const calls = [];
  document.execCommand = (cmd, _ui, value) => {
    calls.push([cmd, value]);
    return true;
  };
  e._handleCommand(payload);
  return calls;
}

test("the server's chip is inserted as is", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._preserveTags = ["image"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};

  const chip = '<span class="leaf-atomic" data-leaf-tag="Image"><img class="leaf-atomic-media" src="/f/1"></span>';
  const calls = run(e, {
    action: "insert_markdown",
    text: '\n<Image file_uuid="abc"/>\n',
    chip,
  });

  assert.deepEqual(calls, [["insertHTML", chip]]);

  e.cleanup();
});

test("without one the browser builds its own from a preserved tag", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._preserveTags = ["image"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};

  const calls = run(e, { action: "insert_markdown", text: '<Image src="/a.png" alt="A"/>' });

  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "insertHTML");
  assert.match(calls[0][1], /data-leaf-tag="Image"/);

  e.cleanup();
});

test("plain text is inserted as text", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "visual");
  e._preserveTags = ["image"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};

  const calls = run(e, { action: "insert_markdown", text: "hello" });

  assert.deepEqual(calls, [["insertText", "hello"]]);

  e.cleanup();
});

// With the caret next to a chip (or nowhere sensible) the browser's
// insertHTML refuses and returns false. The button then did nothing at all,
// which reads as "broken". The block lands after the caret's block instead.
function refusing(e, payload) {
  document.execCommand = () => false;
  e._handleCommand(payload);
}

const CHIP = '<span class="leaf-atomic leaf-atomic-block" contenteditable="false" data-leaf-tag="Note" data-leaf-raw="&lt;Note/&gt;">Note</span>';

function stub(e) {
  // A real browser keeps the caret when an editor that has it is focused;
  // jsdom's focus() moves it, which is not what is under test.
  e._visualEl.focus = () => {};
  e._preserveTags = ["note"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};
}

test("a refused insert still lands the block, after the caret's block", { skip: dom.skip }, () => {
  const e = dom.editor("<p>one</p><p>two</p>", "hybrid");
  stub(e);
  const range = document.createRange();
  range.setStart(e._visualEl.children[0].firstChild, 1);
  range.collapse(true);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(range);

  refusing(e, { action: "insert_markdown", text: "<Note/>", chip: CHIP });

  const kids = [...e._visualEl.children];
  assert.equal(kids.length, 3);
  assert.equal(kids[0].textContent, "one");
  assert.ok(kids[1].querySelector("[data-leaf-tag='Note']"), "the chip is the second block");
  assert.equal(kids[2].textContent, "two");

  e.cleanup();
});

test("with no caret in the editor the block goes to the end, with a paragraph to type in", { skip: dom.skip }, () => {
  const e = dom.editor("<p>one</p>", "hybrid");
  stub(e);
  window.getSelection().removeAllRanges();

  refusing(e, { action: "insert_markdown", text: "<Note/>", chip: CHIP });

  const kids = [...e._visualEl.children];
  assert.equal(kids.length, 3);
  assert.ok(kids[1].querySelector("[data-leaf-tag='Note']"));
  assert.equal(kids[2].tagName, "P", "an editable line after the chip");

  e.cleanup();
});

test("the text path is untouched when insertText is refused", { skip: dom.skip }, () => {
  const e = dom.editor("<p>one</p>", "visual");
  stub(e);

  refusing(e, { action: "insert_markdown", text: "hello" });

  assert.equal(e._visualEl.children.length, 1);

  e.cleanup();
});
