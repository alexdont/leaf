"use strict";

// Entering a rendered block puts its text into source form, escaping what
// markdown would read as syntax (`price *is* 5` becomes `price \*is\* 5`).
// The caret has to move with the text: it was mapped from the offset in the
// UNESCAPED text, so it landed one character short for every backslash
// before it, and the next keystroke went into the wrong place.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function caretIn(html, offset) {
  const e = dom.editor(html, "hybrid");
  const p = e._visualEl.firstChild;
  const out = e._serializeBlockInline(p, p.firstChild, offset);
  e.cleanup();
  return out.source.slice(0, out.cursorOffset) + "|" + out.source.slice(out.cursorOffset);
}

test("a caret after escaped characters stays after them", { skip: dom.skip }, () => {
  assert.equal(caretIn("<p>price *is* 5</p>", 9), "price \\*is|\\* 5");
  assert.equal(caretIn("<p>price *is* 5</p>", 12), "price \\*is\\* 5|");
});

test("a caret right before an escaped character stays before its backslash", { skip: dom.skip }, () => {
  assert.equal(caretIn("<p>price *is* 5</p>", 6), "price |\\*is\\* 5");
});

test("line-start escapes and brackets count too", { skip: dom.skip }, () => {
  assert.equal(caretIn("<p># todo [x]</p>", 9), "\\# todo \\[x|]");
  assert.equal(caretIn("<p># todo [x]</p>", 10), "\\# todo \\[x]|");
});

test("a backslash that is itself escaped", { skip: dom.skip }, () => {
  assert.equal(caretIn("<p>a\\*b</p>", 4), "a\\\\\\*b|");
});

test("nothing to escape: unchanged", { skip: dom.skip }, () => {
  assert.equal(caretIn("<p>plain text</p>", 5), "plain| text");
});
