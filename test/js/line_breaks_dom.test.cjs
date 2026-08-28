"use strict";

// A line break in the middle of a paragraph.
//
// The host renders with hardbreaks on, so a plain newline in the markdown comes
// back as a <br> and the round trip is stable. What was missing is that the
// <br> occupied no position in the coordinates sessions share: pressing Enter
// changed the markdown but not, as far as the editor could tell, the text — so
// there was nothing for a peer to apply and the break did not arrive until a
// second one turned it into a paragraph.

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

test("a break serializes as the newline the host renders back", { skip: dom.skip }, () => {
  const e = dom.editor("<p>a<br>b</p>", "hybrid");

  // A plain newline. Writing an explicit hard break instead would serialize
  // the same document one character longer than the one the host holds, and
  // the first keystroke after loading would be refused.
  assert.equal(e._currentMarkdown(), "a\nb");

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
  assert.equal(e._currentMarkdown(), "a\nb");

  e.cleanup();
});

test("a paragraph break and a line break are told apart", { skip: dom.skip }, () => {
  const line = dom.editor("<p>a<br>b</p>", "hybrid");
  const para = dom.editor("<p>a</p><p>b</p>", "hybrid");

  assert.equal(line._currentMarkdown(), "a\nb");
  assert.equal(para._currentMarkdown(), "a\n\nb");

  // They look the same on screen, and must: one line break either way.
  assert.equal(line._visibleText(line._visualEl), para._visibleText(para._visualEl));

  line.cleanup();
  para.cleanup();
});

// The regression this file exists to prevent a repeat of.
//
// A host stores markdown and renders it for the editor. If the editor
// serializes that same document to anything other than what the host is
// holding, the first keystroke after loading describes a document nobody has
// and is refused — the warning, and a caret thrown across the page, from
// having typed one character into a document nobody had touched.
test("the editor serializes a rendered document back to what was stored", { skip: dom.skip }, () => {
  // What a host stores, and what it renders with hardbreaks on. Verified
  // against the running server.
  const stored = "one\ntwo\n\n- three\n- four";
  const rendered =
    "<p>one<br />\ntwo</p>\n<ul>\n<li>three</li>\n<li>four</li>\n</ul>\n";

  const e = receive(rendered);

  assert.equal(
    e._currentMarkdown(),
    stored,
    "a document that came from the host must go back to the host unchanged"
  );

  e.cleanup();
});

test("a soft break in stored markdown is not rewritten on the way back", { skip: dom.skip }, () => {
  const e = receive("<p>a<br />\nb</p>");

  assert.equal(e._currentMarkdown().length, "a\nb".length, "no character may be added");
  assert.equal(e._currentMarkdown(), "a\nb");

  e.cleanup();
});
