"use strict";

// Showing where other people's carets are.
//
// The coordinate system is the point: offsets are into the rendered text with
// hybrid mode's markdown markers excluded, because that is the only view of the
// document every session shares. Hybrid shows the raw markdown of whichever
// block each person's own caret is in, so a plain DOM offset means something
// different in every tab.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function awarenessEditor(html, mode = "visual") {
  const e = dom.editor(html, mode);

  // In the app the hook root is a wrapper around the editable surface; the
  // shared harness collapses the two into one node. Separate them here,
  // because "the caret layer is never inside the editable text" is precisely
  // what this file has to be able to check — anything added inside the text
  // would be serialized into the document.
  const wrapper = document.createElement("div");
  e._visualEl.parentNode.insertBefore(wrapper, e._visualEl);
  wrapper.appendChild(e._visualEl);
  e.el = wrapper;

  const inner = e.cleanup;
  e.cleanup = () => {
    inner();
    wrapper.remove();
  };

  e._collabAwareness = true;
  e._peerCursors = [];
  return e;
}

// jsdom does no layout, so every getBoundingClientRect is zeroes and the real
// _rectAtVisibleOffset gives up. Geometry is not what these tests are for —
// stub it so the drawing logic underneath is actually exercised, rather than
// passing because nothing was ever drawn.
function withFakeLayout(e) {
  e.el.getBoundingClientRect = () => ({ left: 0, top: 0, width: 400, height: 200 });
  e._rectAtVisibleOffset = (offset) => ({
    left: 10 + offset,
    top: 20,
    width: 0,
    height: 16,
  });
  return e;
}

test("a peer's offset is placed in this editor's text", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>hello world</p>");

  const point = e._visibleNodeAt(6);
  assert.equal(point.node.nodeValue, "hello world");
  assert.equal(point.offset, 6, "offset 6 is the start of 'world'");

  e.cleanup();
});

test("peer offsets skip source markers, so they mean the same in every tab", { skip: dom.skip }, () => {
  const withMarker = awarenessEditor(
    '<ul><li data-leaf-source="li">' +
      '<span class="leaf-source-marker leaf-list-marker">- </span>item</li></ul>',
    "hybrid"
  );
  const without = awarenessEditor("<ul><li>item</li></ul>", "hybrid");

  // The same character in both, despite one DOM carrying a "- " the other lacks.
  const a = withMarker._visibleNodeAt(2);
  const b = without._visibleNodeAt(2);

  assert.equal(a.node.nodeValue.slice(a.offset), "em");
  assert.equal(b.node.nodeValue.slice(b.offset), "em");

  withMarker.cleanup();
  without.cleanup();
});

test("carets are drawn on their own layer, never inside the text", { skip: dom.skip }, () => {
  const e = withFakeLayout(awarenessEditor("<p>hello world</p>"));

  e._renderPeerCursors([{ id: "abc", label: "abc", color: "#f00", offset: 6 }]);

  const layer = e.el.querySelector(".leaf-peer-cursors");
  assert.ok(layer, "a cursor layer should exist");
  assert.equal(layer.getAttribute("aria-hidden"), "true");
  assert.equal(layer.childNodes.length, 1, "the peer's caret should have been drawn");

  const caret = layer.firstChild;
  assert.equal(caret.textContent, "abc", "labelled with who it belongs to");
  assert.equal(caret.style.left, "16px", "positioned from the peer's offset");

  // Two people must be told apart by colour, whatever the CSSOM normalises the
  // value to.
  e._renderPeerCursors([
    { id: "abc", label: "abc", color: "#e11d48", offset: 2 },
    { id: "def", label: "def", color: "#2563eb", offset: 6 },
  ]);

  const drawn = e.el.querySelector(".leaf-peer-cursors").childNodes;
  assert.equal(drawn.length, 2);
  assert.notEqual(
    drawn[0].style.backgroundColor,
    drawn[1].style.backgroundColor,
    "two peers must not be drawn in the same colour"
  );

  // The document itself must be untouched — anything added inside the editable
  // text would be serialized into the markdown.
  assert.equal(e._visualEl.textContent, "hello world");

  e.cleanup();
});

test("rendering replaces the previous carets rather than stacking them", { skip: dom.skip }, () => {
  const e = withFakeLayout(awarenessEditor("<p>hello world</p>"));
  const cursor = { id: "abc", label: "abc", color: "#f00", offset: 3 };

  e._renderPeerCursors([cursor]);
  e._renderPeerCursors([cursor]);
  e._renderPeerCursors([cursor]);

  const layer = e.el.querySelector(".leaf-peer-cursors");
  assert.equal(layer.childNodes.length, 1, "carets must not accumulate on redraw");

  e.cleanup();
});

test("an empty list clears everyone's caret", { skip: dom.skip }, () => {
  const e = withFakeLayout(awarenessEditor("<p>hello world</p>"));

  e._renderPeerCursors([{ id: "abc", label: "abc", color: "#f00", offset: 3 }]);
  assert.equal(e.el.querySelector(".leaf-peer-cursors").childNodes.length, 1);

  e._renderPeerCursors([]);

  const layer = e.el.querySelector(".leaf-peer-cursors");
  assert.equal(layer.childNodes.length, 0);

  e.cleanup();
});

test("a caret is reported once per position, not once per selectionchange", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>hello world</p>");

  const sent = [];
  e.pushEventTo = (_el, name, payload) => sent.push([name, payload]);

  const text = e._visualEl.querySelector("p").firstChild;
  const range = document.createRange();
  range.setStart(text, 4);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  e._emitAwareness();
  e._emitAwareness();
  e._emitAwareness();

  assert.equal(sent.length, 1, "an unmoved caret must not be re-sent");
  // debug is null unless a host turns diagnostics on — nothing extra rides
  // along by default.
  assert.deepEqual(sent[0][1], {
    editor_id: "test-editor",
    offset: 4,
    focused: true,
    debug: null,
  });

  e.cleanup();
});

test("leaving the editor reports no caret at all", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>hello world</p>");

  const sent = [];
  e.pushEventTo = (_el, name, payload) => sent.push(payload);

  const text = e._visualEl.querySelector("p").firstChild;
  const range = document.createRange();
  range.setStart(text, 4);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  e._emitAwareness();
  e._emitAwareness(true);

  assert.equal(sent.length, 2);
  assert.deepEqual(sent[1], {
    editor_id: "test-editor",
    offset: null,
    focused: false,
    debug: null,
  });

  e.cleanup();
});

// A peer's caret is an offset into text that a remote edit just moved. The
// shift is already known, so it is applied rather than leaving their caret
// pointing at the wrong character until they next type.
test("a remote edit moves the peers' carets with the text", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>hello world</p>");
  e._currentMarkdown = () => "big hello world";
  e._peerCursors = [{ id: "abc", label: "abc", color: "#f00", offset: 8 }];

  e._applyRemoteOperation({
    content: "big hello world",
    html: "<p>big hello world</p>",
    at: 0,
    remove: 0,
    insert: "big ",
  });

  assert.equal(e._peerCursors[0].offset, 12, "the peer's caret should ride the insertion");

  e.cleanup();
});

test("awareness stays off unless the host asks for it", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>");
  e._collabAwareness = false;

  const sent = [];
  e.pushEventTo = (_el, name, payload) => sent.push(payload);

  e._emitAwareness();

  assert.deepEqual(sent, [], "no awareness traffic without the opt-in");

  e.cleanup();
});

// ---------------------------------------------------------------------------
// Placeholders must not move the shared coordinates
// ---------------------------------------------------------------------------
//
// An empty list item gets a zero-width placeholder so the caret has somewhere
// to sit, and whether a given item has one depends on what that session has
// been doing. Counting them made two people looking at the same document
// disagree about where a character is: their carets landed in different
// places, and an edit sent from one applied at the wrong offset in the other.

const ZWSP = "​";

test("a placeholder does not shift the shared coordinates", { skip: dom.skip }, () => {
  const bare = awarenessEditor("<ul><li>alpha</li><li></li></ul>", "hybrid");
  const held = awarenessEditor("<ul><li>alpha</li><li>" + ZWSP + "</li></ul>", "hybrid");

  assert.equal(
    bare._visibleText(bare._visualEl),
    held._visibleText(held._visualEl),
    "two sessions on the same document must read the same text"
  );

  bare.cleanup();
  held.cleanup();
});

test("the same character has the same offset either way", { skip: dom.skip }, () => {
  const held = awarenessEditor(
    "<ul><li>" + ZWSP + "</li><li>alpha</li></ul>",
    "hybrid"
  );
  const bare = awarenessEditor("<ul><li></li><li>alpha</li></ul>", "hybrid");

  // The "l" of "alpha" is at the same place in both, placeholder or not.
  const heldPoint = held._visibleNodeAt(1);
  const barePoint = bare._visibleNodeAt(1);

  assert.equal(heldPoint.node.nodeValue.charAt(heldPoint.offset), "l");
  assert.equal(barePoint.node.nodeValue.charAt(barePoint.offset), "l");

  // And reporting a caret there gives the same offset in both.
  assert.equal(
    held._visibleOffset(heldPoint.node, heldPoint.offset),
    bare._visibleOffset(barePoint.node, barePoint.offset)
  );

  held.cleanup();
  bare.cleanup();
});

test("an edit is not written across a placeholder", { skip: dom.skip }, () => {
  const e = awarenessEditor("<ul><li>a" + ZWSP + "b</li></ul>", "hybrid");

  // Visible offsets say "remove 1 at 1" means the "b". Real offsets do not,
  // because the placeholder sits between them — so the shortcut must decline.
  assert.equal(
    e._applyRemoteFastPath({ rendered: { at: 1, remove: 1, insert: "" } }),
    false,
    "a node holding a placeholder must be left to the slow path"
  );

  e.cleanup();
});

// ---------------------------------------------------------------------------
// Line breaks need a position of their own
// ---------------------------------------------------------------------------
//
// Without one, the end of a line and the start of the next are the same
// offset, and an edit sent at that offset lands in whichever of the two the
// receiver resolves it to. That is how one tab ended up with "a body what" /
// "peach tree" while the other had "a bodych tree what" / "pea".

test("the end of a line and the start of the next are different offsets", { skip: dom.skip }, () => {
  const e = awarenessEditor("<ul><li>alpha</li><li>beta</li></ul>", "hybrid");

  assert.equal(e._visibleText(e._visualEl), "alpha\nbeta");

  const endOfAlpha = e._visibleNodeAt(5);
  const startOfBeta = e._visibleNodeAt(6);

  assert.equal(endOfAlpha.node.nodeValue, "alpha");
  assert.equal(endOfAlpha.offset, 5);
  assert.equal(startOfBeta.node.nodeValue, "beta");
  assert.equal(startOfBeta.offset, 0);

  e.cleanup();
});

test("an edit at the start of a line does not land on the one above", { skip: dom.skip }, () => {
  const e = awarenessEditor("<ul><li>alpha</li><li>beta</li></ul>", "hybrid");

  e._applyRemoteFastPath({ rendered: { at: 6, remove: 0, insert: "X" } });

  assert.equal(e._visibleText(e._visualEl), "alpha\nXbeta");

  e.cleanup();
});

test("an edit at the end of a line stays on it", { skip: dom.skip }, () => {
  const e = awarenessEditor("<ul><li>alpha</li><li>beta</li></ul>", "hybrid");

  e._applyRemoteFastPath({ rendered: { at: 5, remove: 0, insert: "X" } });

  assert.equal(e._visibleText(e._visualEl), "alphaX\nbeta");

  e.cleanup();
});

test("a removal reaching across a line break is left to the slow path", { skip: dom.skip }, () => {
  const e = awarenessEditor("<ul><li>alpha</li><li>beta</li></ul>", "hybrid");

  assert.equal(
    e._applyRemoteFastPath({ rendered: { at: 3, remove: 5, insert: "" } }),
    false,
    "the shortcut cannot delete across a line it does not model"
  );
  assert.equal(e._visibleText(e._visualEl), "alpha\nbeta", "and must not have half-done it");

  e.cleanup();
});

// An empty list item holds no text node at all, so the break around it cannot
// be inferred from text — and a session that has put a placeholder in one
// would otherwise see a line where a session that has not sees nothing.
test("an empty line counts the same with or without its placeholder", { skip: dom.skip }, () => {
  const bare = awarenessEditor("<ul><li>alpha</li><li></li></ul>", "hybrid");
  const held = awarenessEditor("<ul><li>alpha</li><li>" + ZWSP + "</li></ul>", "hybrid");

  assert.equal(bare._visibleText(bare._visualEl), "alpha\n");
  assert.equal(
    held._visibleText(held._visualEl),
    bare._visibleText(bare._visualEl),
    "two sessions on the same document must read the same text"
  );

  bare.cleanup();
  held.cleanup();
});

test("headings and paragraphs are separated too", { skip: dom.skip }, () => {
  const e = awarenessEditor("<h1>Title</h1><p>body</p>");

  assert.equal(e._visibleText(e._visualEl), "Title\nbody");

  e.cleanup();
});

// Inline formatting is not a line break — a bold run inside a sentence must
// not split it.
test("inline elements do not introduce a break", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>a <strong>bold</strong> word</p>");

  assert.equal(e._visibleText(e._visualEl), "a bold word");

  e.cleanup();
});

// An empty line between two others is a position that belongs to no line's
// text. There is nothing for the shortcut to edit there, so it must decline
// and let the server's HTML place it.
test("an empty line between two others is left to the slow path", { skip: dom.skip }, () => {
  const e = awarenessEditor("<ul><li>a</li><li></li><li>b</li></ul>", "hybrid");

  assert.equal(e._visibleText(e._visualEl), "a\n\nb");

  const point = e._visibleNodeAt(2);
  assert.equal(point.boundary, true, "offset 2 is the empty line itself");

  assert.equal(
    e._applyRemoteFastPath({ rendered: { at: 2, remove: 0, insert: "X" } }),
    false,
    "there is no text node that position belongs to"
  );
  assert.equal(e._visibleText(e._visualEl), "a\n\nb", "and nothing may have been written");

  e.cleanup();
});

// ---------------------------------------------------------------------------
// Whitespace the host never stores
// ---------------------------------------------------------------------------
//
// Leaf substitutes a non-breaking space for a space at the end of a line so it
// stays visible, and markdown trims it away. So the session that typed it held
// one more character than the document, while a session that received that
// document held none — and from there every edit was placed one position out.
// A character was lifted out of one word and dropped into another.

test("whitespace at the end of a line is not part of the shared text", { skip: dom.skip }, () => {
  const typed = awarenessEditor("<p>word </p>");
  const received = awarenessEditor("<p>word</p>");

  assert.equal(typed._visibleText(typed._visualEl), "word");
  assert.equal(
    typed._visibleText(typed._visualEl),
    received._visibleText(received._visualEl),
    "the writer and the reader must count the same characters"
  );

  typed.cleanup();
  received.cleanup();
});

test("the same applies to a list item and a heading", { skip: dom.skip }, () => {
  const item = awarenessEditor("<ul><li>word </li></ul>", "hybrid");
  const heading = awarenessEditor("<h1>word </h1>", "hybrid");

  assert.equal(item._visibleText(item._visualEl), "word");
  assert.equal(heading._visibleText(heading._visualEl), "word");

  item.cleanup();
  heading.cleanup();
});

test("whitespace inside a line is text and stays", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>a b</p>");

  assert.equal(e._visibleText(e._visualEl), "a b", "only trailing whitespace is trimmed");

  e.cleanup();
});

test("a caret past the trailing space still reports the end of the line", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>word </p>");
  const text = e._visualEl.querySelector("p").firstChild;

  // The caret sits after the invisible space; there are only four characters.
  assert.equal(e._visibleOffset(text, 5), 4);

  e.cleanup();
});

test("an offset resolves past trailing whitespace to the real position", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>word </p>");

  const point = e._visibleNodeAt(4);
  assert.equal(point.node.nodeValue, "word ");
  assert.equal(point.offset, 5, "the end of the line is past the space, in real terms");

  e.cleanup();
});

// replaceData counts real characters, so the shortcut can only be used where
// the two kinds of offset coincide.
test("the shortcut declines a line ending in invisible whitespace", { skip: dom.skip }, () => {
  const e = awarenessEditor("<p>word </p>");

  assert.equal(
    e._applyRemoteFastPath({ rendered: { at: 2, remove: 1, insert: "X" } }),
    false,
    "writing with shared offsets into a node that holds untracked characters is wrong"
  );
  assert.equal(e._visibleText(e._visualEl), "word", "and nothing may have been written");

  e.cleanup();
});
