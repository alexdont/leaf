"use strict";

// Pasting a copied line must stay in the line.
//
// Triple-clicking a line and copying it makes Chrome put the line on the
// clipboard as `<p style="…">text</p><br class="Apple-interchange-newline">`
// (text/plain "text\n\n"). Inserted as-is, every paste opened a new
// paragraph and left a stray <br>, so Ctrl+V, Ctrl+V, Ctrl+V gave three
// lines instead of the text three times on one line. Only a copy that
// really carries a line break (a second, empty paragraph) may open a line.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

const CHROME_LINE =
  '<p style="margin: 0.5em 0px; color: rgb(0, 0, 0);">hello</p>' +
  '<br class="Apple-interchange-newline">';

function paste(e, data) {
  const inserted = [];
  document.execCommand = (cmd, _ui, value) => {
    inserted.push([cmd, value]);
    return true;
  };

  const evt = {
    type: "paste",
    clipboardData: {
      items: [],
      files: [],
      getData: (kind) => data[kind] || "",
    },
    prevented: false,
    preventDefault() {
      this.prevented = true;
    },
  };
  e._onPaste(evt);
  return { evt, inserted };
}

test("a copied line pastes as its text, not as a new paragraph", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { evt, inserted } = paste(e, { "text/html": CHROME_LINE, "text/plain": "hello\n\n" });

  assert.equal(evt.prevented, true);
  assert.deepEqual(inserted, [["insertHTML", "hello"]]);

  e.cleanup();
});

test("inline formatting inside the copied line survives", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, {
    "text/html": "<p>say <strong>hi</strong></p>",
    "text/plain": "say hi",
  });

  assert.deepEqual(inserted, [["insertHTML", "say <strong>hi</strong>"]]);

  e.cleanup();
});

test("a div-wrapped line (other apps) pastes inline too", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, { "text/html": "<div>one line</div>", "text/plain": "one line" });

  assert.deepEqual(inserted, [["insertHTML", "one line"]]);

  e.cleanup();
});

test("a copy that carries a real line break still opens a line", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, {
    "text/html": "<p>hello</p><p><br></p>",
    "text/plain": "hello\n",
  });

  assert.equal(inserted.length, 1);
  assert.match(inserted[0][1], /<p>hello<\/p><p><br><\/p>/);

  e.cleanup();
});

test("several paragraphs keep their blocks", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, {
    "text/html": "<p>one</p><p>two</p>",
    "text/plain": "one\n\ntwo",
  });

  assert.equal(inserted[0][1], "<p>one</p><p>two</p>");

  e.cleanup();
});

test("a heading or a list is a block and stays one", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");

  assert.equal(paste(e, { "text/html": "<h2>title</h2>" }).inserted[0][1], "<h2>title</h2>");
  assert.equal(
    paste(e, { "text/html": "<ul><li>a</li></ul>" }).inserted[0][1],
    "<ul><li>a</li></ul>"
  );

  e.cleanup();
});

test("a paragraph holding a block inside is left alone", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, { "text/html": "<div><p>a</p><p>b</p></div>" });

  assert.equal(inserted[0][1], "<div><p>a</p><p>b</p></div>");

  e.cleanup();
});
