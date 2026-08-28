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
  // The one function every arrival point uses, so a test cannot pass against
  // a call site that quietly does less than the others.
  e._normalizeRenderedHtml(e._visualEl);
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

// The failure this file was written for, reduced.
//
// A session that had loaded the page counted the newline html pretty-printing
// writes after a <br />, while a session that had received the same document
// had it stripped. Same document, same fingerprint, one character apart in the
// coordinates — so every caret and every edit past that point was one place
// out. Three arrival points, and one of them did less than the other two.
test("a loaded session counts what a receiving session counts", { skip: dom.skip }, () => {
  // Exactly what the host sends for "…tab on\nthis page sees it arrive."
  const html = "<p>every other tab on<br />\nthis page sees it arrive.</p>\n";

  const loaded = receive(html);
  const received = receive(html);

  assert.equal(
    loaded._visibleText(loaded._visualEl),
    "every other tab on\nthis page sees it arrive.",
    "one line break, not two"
  );

  assert.equal(
    loaded._visibleText(loaded._visualEl),
    received._visibleText(received._visualEl)
  );

  loaded.cleanup();
  received.cleanup();
});

test("normalizing twice changes nothing", { skip: dom.skip }, () => {
  const e = receive("<p>a<br />\nb</p>\n<p>c</p>\n");
  const once = e._visibleText(e._visualEl);

  e._normalizeRenderedHtml(e._visualEl);

  assert.equal(e._visibleText(e._visualEl), once, "arriving twice must not add a line");

  e.cleanup();
});

// Every path that puts the host's html into the editor has to normalize it,
// and there turned out to be four of them: the page loading, html pushed
// mid-session, a whole document replaced, and a mode switch back to the visual
// surface. Three did and one did not, so a session that had been handed a
// replacement document counted a character the others did not, and every caret
// past that point was one place out.
//
// The check is on the result rather than on the call: whichever way this html
// arrives, the editor must end up counting the same characters.
const HOST_HTML = "<h1>Collaboration testbed</h1>\n<p>Type here.</p>\n";
const EXPECTED = "Collaboration testbed\nType here.";

test("html arriving un-normalized counts a line that is not there", { skip: dom.skip }, () => {
  const e = dom.editor(HOST_HTML, "hybrid");

  // Without normalizing, the newline between the two blocks is counted twice:
  // once as the break between them and once as the text node itself.
  assert.equal(e._visibleText(e._visualEl), "Collaboration testbed\n\nType here.\n");

  e.cleanup();
});

test("a document replaced by the host counts the same as one loaded", { skip: dom.skip }, () => {
  const loaded = receive(HOST_HTML);

  // What set_content does: replace the content, then normalize.
  const replaced = dom.editor("<p>something else</p>", "hybrid");
  replaced._visualEl.innerHTML = HOST_HTML;
  replaced._normalizeRenderedHtml(replaced._visualEl);
  replaced._ensureListItemPlaceholders(replaced._visualEl);

  assert.equal(loaded._visibleText(loaded._visualEl), EXPECTED);
  assert.equal(
    replaced._visibleText(replaced._visualEl),
    loaded._visibleText(loaded._visualEl),
    "a session handed a replacement must count what a session that loaded it counts"
  );

  loaded.cleanup();
  replaced.cleanup();
});
