"use strict";

// Two sessions must agree on how many characters the document has.
//
// They can hold the same document — same markdown, same length, same
// fingerprint — and still disagree about that, because the coordinates come
// from the DOM and one session's DOM was built by typing while the other's was
// rendered by the host. When they disagree by one, every offset after that
// point means a different place in each, and text typed after a full stop
// arrives before it.
//
// The html here is what the host really produces, checked against the running
// server with the render options the app uses (hardbreaks on).

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function receive(html) {
  const e = dom.editor(html, "hybrid");
  e._stripInterBlockWhitespace(e._visualEl);
  e._stripBreakWhitespace(e._visualEl);
  e._unwrapLooseListItems(e._visualEl);
  e._ensureListItemPlaceholders(e._visualEl);
  return e;
}

const CASES = [
  {
    name: "paragraphs",
    markdown: "a\n\nb",
    html: "<p>a</p>\n<p>b</p>\n",
    visible: "a\nb",
  },
  {
    name: "heading, paragraph and a list",
    markdown: "# H\n\npara\n\n- one\n- two",
    html: "<h1>H</h1>\n<p>para</p>\n<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n",
    visible: "H\npara\none\ntwo",
  },
  {
    name: "a soft line break",
    markdown: "para\nsoft break",
    html: "<p>para<br />\nsoft break</p>\n",
    visible: "para\nsoft break",
  },
  {
    name: "a sentence ending in a full stop",
    markdown: "text.",
    html: "<p>text.</p>\n",
    visible: "text.",
  },
  {
    name: "an empty item between two others",
    markdown: "- one\n- \n- three",
    html: "<ul>\n<li>one</li>\n<li></li>\n<li>three</li>\n</ul>\n",
    visible: "one\n\nthree",
  },
];

for (const example of CASES) {
  test(`coordinates for ${example.name}`, { skip: dom.skip }, () => {
    const e = receive(example.html);

    assert.equal(
      e._visibleText(e._visualEl),
      example.visible,
      "the shared coordinates must be what every session counts"
    );

    assert.equal(
      e._currentMarkdown(),
      example.markdown,
      "and the document must go back to the host unchanged"
    );

    e.cleanup();
  });
}

// The end of a sentence is where this went wrong for a writer: text typed
// after a full stop arrived before it, because the two sessions counted a
// different number of characters up to that point.
test("the end of a line is the same offset in a receiving session", { skip: dom.skip }, () => {
  const e = receive("<p>text.</p>\n");

  assert.equal(e._visibleText(e._visualEl).length, 5);

  // Offset 5 is after the full stop, and must resolve past it.
  const point = e._visibleNodeAt(5);
  assert.equal(point.node.nodeValue.slice(0, point.offset), "text.");

  e.cleanup();
});

test("a trailing empty line is counted, once", { skip: dom.skip }, () => {
  const e = receive("<ul>\n<li>one</li>\n<li></li>\n</ul>\n");

  assert.equal(
    e._visibleText(e._visualEl),
    "one\n",
    "the empty item is a line, and exactly one"
  );

  e.cleanup();
});
