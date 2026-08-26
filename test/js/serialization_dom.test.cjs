"use strict";

// HTML → markdown, against a real DOM.
//
// `htmlToMarkdown` parses by assigning `innerHTML` and walking the result, so
// it cannot be tested without a DOM at all. It is also the half of the
// server↔client contract the client owns: whatever it emits is what the
// document becomes, so a list item lost here is lost for good.
//
// Reached through `_currentMarkdown`, since the conversion itself lives inside
// the bundle's IIFE and is not exported.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor, ZWSP } = require("./support/dom.cjs");

function markdownOf(html) {
  const e = editor(html);
  const md = e._currentMarkdown();
  e.cleanup();
  return md;
}

test("an empty item mid-list serializes as its own line", { skip }, () => {
  // The whole point: a blank row has to survive the trip to markdown, or the
  // next render brings back a list with one fewer item.
  assert.equal(
    markdownOf("<ul><li>one</li><li></li><li>three</li></ul>"),
    "- one\n- \n- three"
  );
});

test("the zero-width placeholder never becomes content", { skip }, () => {
  // It exists only to give the caret somewhere to sit; if it reached the
  // document, every empty bullet would hold an invisible character.
  assert.equal(
    markdownOf(`<ul><li>one</li><li>${ZWSP}</li><li>three</li></ul>`),
    "- one\n- \n- three"
  );
});

test("a <br> filler is treated the same as an empty item", { skip }, () => {
  assert.equal(
    markdownOf("<ul><li>one</li><li><br></li><li>three</li></ul>"),
    "- one\n- \n- three"
  );
});

test("ordered lists keep their numbering across a blank item", { skip }, () => {
  assert.equal(
    markdownOf("<ol><li>one</li><li></li><li>three</li></ol>"),
    "1. one\n2. \n3. three"
  );
});

test("nested lists survive round-tripping", { skip }, () => {
  const md = markdownOf(
    "<ul><li>one<ul><li>nested</li></ul></li><li>two</li></ul>"
  );

  assert.match(md, /- one/);
  assert.match(md, /^ {2}- nested$/m, "nested item must be indented past the marker");
  assert.match(md, /- two/);
});

test("an item's text is preserved verbatim", { skip }, () => {
  assert.equal(markdownOf("<ul><li>hello world</li></ul>"), "- hello world");
});


// ---------------------------------------------------------------------------
// Ordered lists that do not start at 1.
//
// Authors write them: a list continuing one interrupted by a paragraph, or
// steps numbered on from an earlier section. CommonMark preserves it — `19.`
// renders as `<ol start="19">` — but the serializer counted from 1 regardless,
// so every trip out to markdown silently renumbered the document. Switching
// modes was the visible symptom.
// ---------------------------------------------------------------------------

test("a list starting at 19 keeps its numbering", { skip }, () => {
  assert.equal(
    markdownOf('<ol start="19"><li>nineteen</li><li>twenty</li><li>twenty-one</li></ol>'),
    "19. nineteen\n20. twenty\n21. twenty-one"
  );
});

test("a list with no start attribute still counts from 1", { skip }, () => {
  assert.equal(markdownOf("<ol><li>one</li><li>two</li></ol>"), "1. one\n2. two");
});

test("an explicit start of 1 and no start agree", { skip }, () => {
  assert.equal(
    markdownOf('<ol start="1"><li>one</li></ol>'),
    markdownOf("<ol><li>one</li></ol>")
  );
});

test("a nested list keeps its own start", { skip }, () => {
  const md = markdownOf('<ol start="19"><li>a<ol start="3"><li>inner</li></ol></li></ol>');

  assert.match(md, /^19\. a$/m);
  assert.match(md, /^ {3}3\. inner$/m);
});

test("a malformed start attribute falls back to 1 rather than NaN", { skip }, () => {
  assert.equal(markdownOf('<ol start="abc"><li>one</li></ol>'), "1. one");
});
