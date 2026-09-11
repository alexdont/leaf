"use strict";

// Ctrl+Backspace / Ctrl+Delete in a hybrid source block.
//
// Chrome's native word-delete runs its selection through hidden marker
// spans and non-editable chrome and silently refuses the edit — the
// "keydown with no beforeinput" abort. So the word variant goes through
// the same source-string surgery single-char deletes use, and this file
// pins the span it removes.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

function span(text, offset, backward) {
  const e = editor("<p>x</p>", "hybrid");
  const out = e._wordDeleteSpan(text, offset, backward);
  e.cleanup();
  return out;
}

test("backward takes the word before the caret", { skip }, () => {
  assert.deepEqual(span("hello world", 11, true), [6, 11]);
});

test("backward eats the whitespace touching the caret first", { skip }, () => {
  assert.deepEqual(span("hello world  ", 13, true), [6, 13]);
});

test("backward stops at a symbol/word boundary", { skip }, () => {
  // `.` belongs to the symbol run, `bar` to the word run — one run per press.
  assert.deepEqual(span("foo.bar", 7, true), [4, 7]);
  assert.deepEqual(span("foo.bar", 4, true), [3, 4]);
});

test("backward treats a symbol run as one word", { skip }, () => {
  assert.deepEqual(span("foo --- ", 8, true), [4, 8]);
});

test("placeholder characters count as skippable space", { skip }, () => {
  assert.deepEqual(span("foo ​bar​", 9, true), [5, 9]);
});

test("forward takes the word after the caret", { skip }, () => {
  assert.deepEqual(span("hello world", 0, false), [0, 5]);
});

test("forward eats the whitespace touching the caret first", { skip }, () => {
  assert.deepEqual(span("hello world", 5, false), [5, 11]);
});

test("nothing to take leaves the span empty", { skip }, () => {
  assert.deepEqual(span("abc", 0, true), [0, 0]);
  assert.deepEqual(span("abc", 3, false), [3, 3]);
});
