"use strict";

// Applying someone else's edit without stealing this user's caret.
//
// This is the behaviour the collaboration spec calls the point that makes or
// breaks the feel, and it cannot be checked without a real DOM: the whole
// question is where a Range ends up after innerHTML is replaced underneath it.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

// Where the caret sits, as an offset into the editor's rendered text.
function caretOffset(e) {
  const sel = window.getSelection();
  if (!sel.rangeCount) return null;
  const range = sel.getRangeAt(0);
  return e._historyTextOffset(range.startContainer, range.startOffset);
}

// Put the caret at `offset` characters into the rendered text.
function placeCaret(e, offset) {
  const point = e._historyNodeAt(offset);
  const range = document.createRange();
  range.setStart(point.node, point.offset);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}

// A remote edit arrives as the full new document plus the splice that made it.
function remote(e, html, op) {
  e._applyRemoteOperation({
    content: op.content || "",
    html,
    at: op.at,
    remove: op.remove || 0,
    insert: op.insert || "",
  });
}

test("_shiftOffset moves a caret only when the edit lands before it", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>");

  const splice = { at: 5, remove: 0, insert: "XYZ" };

  assert.equal(e._shiftOffset(2, splice), 2, "an edit after the caret must not move it");
  assert.equal(e._shiftOffset(5, splice), 5, "an edit exactly at the caret must not move it");
  assert.equal(e._shiftOffset(9, splice), 12, "an edit before the caret shifts it by the insert");

  const deletion = { at: 0, remove: 4, insert: "" };
  assert.equal(e._shiftOffset(10, deletion), 6, "a deletion before the caret pulls it back");

  // The caret was inside text someone else replaced. There is no position that
  // survives, so it goes to the end of what they wrote.
  const replacement = { at: 2, remove: 6, insert: "ab" };
  assert.equal(e._shiftOffset(5, replacement), 4);

  e.cleanup();
});

test("a peer's edit before the caret keeps the caret on the same character", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello world</p>");
  e._currentMarkdown = () => "hello world";

  placeCaret(e, 8); // between "wo" and "rld"
  assert.equal(caretOffset(e), 8);

  // A peer typed "big " at the start.
  remote(e, "<p>big hello world</p>", { at: 0, remove: 0, insert: "big ", content: "big hello world" });

  assert.equal(e._visualEl.textContent, "big hello world");
  assert.equal(caretOffset(e), 12, "the caret should still be between 'wo' and 'rld'");

  e.cleanup();
});

test("a peer's edit after the caret leaves the caret exactly where it was", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello world</p>");
  e._currentMarkdown = () => "hello world";

  placeCaret(e, 3);

  remote(e, "<p>hello world!!</p>", { at: 11, remove: 0, insert: "!!", content: "hello world!!" });

  assert.equal(caretOffset(e), 3, "an edit further down the document must not move the caret");

  e.cleanup();
});

// The operation is in markdown offsets; the caret is in rendered text. A
// heading's "# " exists in one and not the other. The caret here sits between
// the two offsets, which is the only place the difference is observable — put
// it anywhere else and trusting the markdown offset gives the same answer.
test("markdown markers do not skew the restored caret", { skip: dom.skip }, () => {
  const e = dom.editor("<h1>Title</h1><p>body text</p>");
  e._currentMarkdown = () => "# Title\n\nbody text";

  // Rendered text is "Titlebody text"; offset 1 is between "T" and "itle".
  placeCaret(e, 1);
  assert.equal(caretOffset(e), 1);

  // The peer inserts "New " before "Title". In markdown that is offset 2,
  // after the "# " marker; on screen it is offset 0.
  remote(e, "<h1>New Title</h1><p>body text</p>", {
    at: 2,
    remove: 0,
    insert: "New ",
    content: "# New Title\n\nbody text",
  });

  // Correct: the caret rides the 4 inserted characters to offset 5, still
  // between "T" and "itle". Trusting the markdown offset (2) would decide the
  // edit landed after the caret and leave it at 1 — inside "New".
  assert.equal(
    caretOffset(e),
    5,
    "caret must shift by the rendered insert, not be judged against the markdown offset"
  );

  e.cleanup();
});

test("applying a remote operation does not emit one back", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>");
  e._currentMarkdown = () => "hello there";
  e._collabOperations = true;
  e._lastSentMarkdown = "hello";

  const sent = [];
  e.pushEventTo = (_el, name, payload) => sent.push([name, payload]);

  // Replacing content fires input events, which reach _emitOperation while the
  // baseline still says "hello" — so it would happily diff the peer's edit and
  // send it back to them as ours. Stand in for that here, mid-swap.
  e._resolveWikiLinks = () => e._emitOperation("hello there");

  remote(e, "<p>hello there</p>", { at: 5, remove: 0, insert: " there", content: "hello there" });

  assert.deepEqual(sent, [], "a remote apply must not push an operation back to its author");
  assert.equal(
    e._lastSentMarkdown,
    "hello there",
    "the baseline must advance, or the next local edit re-sends the peer's change"
  );

  e.cleanup();
});

test("a remote operation is not recorded as this user's undo step", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>");
  e._currentMarkdown = () => "hello!";

  let captured = 0;
  e._historyCapture = () => captured++;

  remote(e, "<p>hello!</p>", { at: 5, remove: 0, insert: "!", content: "hello!" });

  assert.equal(e._historyRestoring, true, "the history guard must be up during the swap");
  assert.equal(captured, 0, "someone else's typing must not enter this user's undo stack");

  e.cleanup();
});

test("a remote edit with no local caret is applied without placing one", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>");
  e._currentMarkdown = () => "hello world";

  window.getSelection().removeAllRanges();

  remote(e, "<p>hello world</p>", { at: 5, remove: 0, insert: " world", content: "hello world" });

  assert.equal(e._visualEl.textContent, "hello world");
  assert.equal(window.getSelection().rangeCount, 0, "must not steal a caret the user never had here");

  e.cleanup();
});

// Hybrid mode shows the block under the caret as raw markdown, in
// leaf-source-marker spans. Those exist in this editor's DOM and never in the
// server's HTML, so a textContent diff counted them as a deletion and pulled
// the caret backwards out of what the user was typing.
test("hybrid source markers do not drag the caret", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<h1>Title</h1><ul><li data-leaf-source="li">' +
      '<span class="leaf-source-marker leaf-list-marker">- </span>what</li></ul>',
    "hybrid"
  );
  e._currentMarkdown = () => "# Title\n\n- what";

  // Caret at the end of "what", where someone typing that item would have it.
  const item = e._visualEl.querySelector("li").lastChild;
  const range = document.createRange();
  range.setStart(item, item.textContent.length);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  assert.equal(e._visibleOffset(item, item.textContent.length), 9, "Title + what");

  // A peer appends a second item — nothing before this caret changes.
  remote(
    e,
    "<h1>Title</h1><ul><li>what</li><li>next</li></ul>",
    { at: 15, remove: 0, insert: "\n- next", content: "# Title\n\n- what\n- next" }
  );

  assert.equal(
    caretOffset(e),
    9,
    "caret must stay at the end of 'what', not be pulled back by the marker"
  );

  e.cleanup();
});

test("_visibleText excludes source markers, _visibleOffset agrees with it", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li data-leaf-source="li">' +
      '<span class="leaf-source-marker leaf-list-marker">- </span>item</li></ul>',
    "hybrid"
  );

  assert.equal(e._visualEl.textContent, "- item", "the marker is really in the DOM");
  assert.equal(e._visibleText(e._visualEl), "item", "and must not be in the comparison text");

  const text = e._visualEl.querySelector("li").lastChild;
  assert.equal(e._visibleOffset(text, 4), 4, "offsets are measured in marker-free text");

  // A caret inside the marker collapses to where the marker begins.
  const marker = e._visualEl.querySelector(".leaf-source-marker").firstChild;
  assert.equal(e._visibleOffset(marker, 1), 0);

  e.cleanup();
});
