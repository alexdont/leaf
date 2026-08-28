"use strict";

// A line break in the middle of a paragraph.
//
// It used to serialize as a bare newline, which is a SOFT break: markdown
// renders it back as a space, so the break was lost on every round trip. In a
// shared document that meant pressing Enter did nothing visible to anyone else
// until a second Enter turned it into a paragraph — and on reload it was gone
// for the author too.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

// What Leaf does to html arriving from the host.
function receive(html) {
  const e = dom.editor(html, "hybrid");
  e._stripInterBlockWhitespace(e._visualEl);
  e._stripBreakWhitespace(e._visualEl);
  e._unwrapLooseListItems(e._visualEl);
  e._ensureListItemPlaceholders(e._visualEl);
  return e;
}

test("a break with text after it becomes a hard break", { skip: dom.skip }, () => {
  const e = dom.editor("<p>a<br>b</p>", "hybrid");

  // Backslash-newline, not a bare newline: the bare one is a soft break and
  // renders back as a space.
  assert.equal(e._currentMarkdown(), "a\\\nb");

  e.cleanup();
});

test("an empty paragraph does not gain a stray marker", { skip: dom.skip }, () => {
  const e = dom.editor("<p><br></p>", "hybrid");

  assert.equal(e._currentMarkdown(), "", "the break is the empty line, not a break in text");

  e.cleanup();
});

test("a break at the end of a block is not a break in the text", { skip: dom.skip }, () => {
  const e = dom.editor("<p>a<br></p>", "hybrid");

  assert.equal(e._currentMarkdown(), "a");

  e.cleanup();
});

test("a filler break is still ignored", { skip: dom.skip }, () => {
  const e = dom.editor('<p>a<br data-leaf-filler="true">b</p>', "hybrid");

  assert.equal(e._currentMarkdown(), "ab", "presentation only, never text");
  assert.equal(
    e._visibleText(e._visualEl),
    "ab",
    "and it must not occupy a position either, or the coordinates gain a line nobody typed"
  );

  e.cleanup();
});

// The whole point: what the author wrote is what everyone else receives.
test("a break survives the trip through the host and back", { skip: dom.skip }, () => {
  const author = dom.editor("<p>a<br>b</p>", "hybrid");
  const markdown = author._currentMarkdown();

  // What MDEx renders that to, verified against the running server.
  const peer = receive("<p>a<br />\nb</p>");

  assert.equal(peer._currentMarkdown(), markdown, "the peer must hold the same document");
  assert.equal(
    peer._visibleText(peer._visualEl),
    author._visibleText(author._visualEl),
    "and agree with the author about where every character is"
  );

  author.cleanup();
  peer.cleanup();
});

test("a hard break occupies a position in the shared coordinates", { skip: dom.skip }, () => {
  const e = dom.editor("<p>ab<br>cd</p>", "hybrid");

  assert.equal(e._visibleText(e._visualEl), "ab\ncd");

  // The character after the break is addressable, and is not the one before it.
  const point = e._visibleNodeAt(3);
  assert.equal(point.node.nodeValue.charAt(point.offset), "c");

  e.cleanup();
});

// MDEx writes "<br />\n". That newline is markup formatting; counted as text it
// reads as a second break, and the two sessions stop agreeing about where every
// later character is.
test("the newline html puts after a break is not text", { skip: dom.skip }, () => {
  const e = receive("<p>a<br />\nb</p>");

  assert.equal(e._visibleText(e._visualEl), "a\nb");
  assert.equal(e._currentMarkdown(), "a\\\nb");

  e.cleanup();
});

test("a paragraph break and a line break are told apart", { skip: dom.skip }, () => {
  const line = dom.editor("<p>a<br>b</p>", "hybrid");
  const para = dom.editor("<p>a</p><p>b</p>", "hybrid");

  assert.equal(line._currentMarkdown(), "a\\\nb");
  assert.equal(para._currentMarkdown(), "a\n\nb");

  // They look the same on screen, and must: one line break either way.
  assert.equal(line._visibleText(line._visualEl), para._visibleText(para._visualEl));

  line.cleanup();
  para.cleanup();
});
