"use strict";

// Wrapping a selection with a bracket or quote.
//
// Select `hello`, press `(`, get `(hello)` — with `hello` still selected, so
// the wrap can be repeated. Without this the keystroke replaced the selection,
// which is what a plain contenteditable does with any printable character.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

const PAIRS = [
  ["(", "(hello) world"],
  ["[", "[hello] world"],
  ["{", "{hello} world"],
  ['"', '"hello" world'],
  ["'", "'hello' world"],
  ["`", "`hello` world"],
];

function pressWithSelection(e, key, range) {
  const sel = window.getSelection();

  sel.removeAllRanges();
  sel.addRange(range);

  const event = new window.KeyboardEvent("keydown", {
    key,
    bubbles: true,
    cancelable: true,
  });

  return e._maybeSurroundSelection(event);
}

function selectWord(e) {
  const text = e._visualEl.children[0].firstChild;
  const range = document.createRange();

  range.setStart(text, 0);
  range.setEnd(text, 5);

  return range;
}

for (const [key, expected] of PAIRS) {
  test(`pressing ${key} wraps the selection`, { skip }, () => {
    const e = editor("<p>hello world</p>", "hybrid");

    const handled = pressWithSelection(e, key, selectWord(e));

    assert.equal(handled, true);
    assert.equal(e._visualEl.textContent, expected);
    e.cleanup();
  });
}

test("the text stays selected, so wraps can be stacked", { skip }, () => {
  const e = editor("<p>hello world</p>", "hybrid");

  pressWithSelection(e, "(", selectWord(e));

  assert.equal(window.getSelection().toString(), "hello");
  e.cleanup();
});

test("wrapping twice nests", { skip }, () => {
  const e = editor("<p>hello</p>", "hybrid");
  const range = document.createRange();
  range.selectNodeContents(e._visualEl.children[0]);

  pressWithSelection(e, "(", range);
  e._maybeSurroundSelection(
    new window.KeyboardEvent("keydown", { key: "[", bubbles: true, cancelable: true })
  );

  assert.equal(e._visualEl.textContent, "([hello])");
  e.cleanup();
});

test("formatting inside the selection is preserved", { skip }, () => {
  // Inserting AROUND the selection rather than replacing its text is what
  // keeps this: `execCommand("insertText")` would flatten the <strong> to
  // plain text and quietly lose the formatting.
  const e = editor("<p><strong>bold</strong> text</p>", "hybrid");
  const range = document.createRange();
  range.selectNodeContents(e._visualEl.children[0]);

  pressWithSelection(e, "(", range);

  assert.match(e._visualEl.innerHTML, /<strong>bold<\/strong>/);
  assert.equal(e._visualEl.textContent, "(bold text)");
  e.cleanup();
});

test("a closing character is not a wrapper", { skip }, () => {
  // It must stay typeable, and pressing it after a wrap should not nest again.
  const e = editor("<p>hello world</p>", "hybrid");

  assert.equal(pressWithSelection(e, ")", selectWord(e)), false);
  assert.equal(e._visualEl.textContent, "hello world");
  e.cleanup();
});

test("with no selection the key types normally", { skip }, () => {
  const e = editor("<p>hello</p>", "hybrid");
  const range = document.createRange();
  range.setStart(e._visualEl.children[0].firstChild, 5);
  range.collapse(true);

  assert.equal(pressWithSelection(e, "(", range), false);
  e.cleanup();
});

test("a modifier combination is left alone", { skip }, () => {
  // Ctrl+[ and friends are shortcuts, not text.
  const e = editor("<p>hello world</p>", "hybrid");
  const sel = window.getSelection();

  sel.removeAllRanges();
  sel.addRange(selectWord(e));

  const event = new window.KeyboardEvent("keydown", {
    key: "[",
    ctrlKey: true,
    bubbles: true,
    cancelable: true,
  });

  assert.equal(e._maybeSurroundSelection(event), false);
  e.cleanup();
});

test("a readonly editor never wraps", { skip }, () => {
  const e = editor("<p>hello world</p>", "hybrid");
  e._readonly = true;

  assert.equal(pressWithSelection(e, "(", selectWord(e)), false);
  e.cleanup();
});

// --------------------------------------------------------------------------
// The textarea surfaces: markdown and html modes.
// --------------------------------------------------------------------------

function textareaCase(value, start, end, key) {
  const e = editor("<p>x</p>", "markdown");
  const ta = document.createElement("textarea");

  ta.value = value;
  document.body.appendChild(ta);
  ta.setSelectionRange(start, end);

  // Force the fallback branch rather than the registered markdown helper,
  // which needs the editor's real textarea in the page.
  e._getMarkdownTextarea = () => null;

  const handled = e._maybeSurroundTextarea(
    new window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
    ta
  );

  const result = { handled, value: ta.value, start: ta.selectionStart, end: ta.selectionEnd };

  ta.remove();
  e.cleanup();
  return result;
}

test("a textarea selection wraps too", { skip }, () => {
  const r = textareaCase("hello world", 0, 5, "(");

  assert.equal(r.handled, true);
  assert.equal(r.value, "(hello) world");
});

test("a textarea keeps the text selected inside the wrap", { skip }, () => {
  const r = textareaCase("hello world", 0, 5, "(");

  assert.equal(r.start, 1);
  assert.equal(r.end, 6);
});

test("a textarea with no selection types the character", { skip }, () => {
  const r = textareaCase("hello", 2, 2, "(");

  assert.equal(r.handled, false);
  assert.equal(r.value, "hello");
});
