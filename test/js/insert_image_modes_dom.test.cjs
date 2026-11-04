"use strict";

// "Insert image by URL" and the host's insert_image command put the picture
// into whichever surface is showing. They used to do nothing in hybrid (the
// default) and html modes, and insert_image always wrote into the hidden
// visual surface.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function capturing(e) {
  const inserted = [];
  document.execCommand = (cmd, _ui, value) => {
    inserted.push([cmd, value]);
    return true;
  };
  e._refreshSourceBlock = () => inserted.push(["refresh"]);
  return inserted;
}

test("hybrid mode inserts into the visual surface and refreshes the source block", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const inserted = capturing(e);

  e._insertImageByUrl("https://x.y/a.png", 'say "hi"', null);

  assert.deepEqual(inserted, [
    ["insertHTML", '<img src="https://x.y/a.png" alt="say &quot;hi&quot;" draggable="true" />'],
    ["refresh"],
  ]);
  e.cleanup();
});

test("html mode inserts the tag into the HTML textarea", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "html");
  const ta = document.createElement("textarea");
  ta.value = "before after";
  ta.selectionStart = ta.selectionEnd = 7;
  document.body.appendChild(ta);
  e._getHtmlTextarea = () => ta;
  e._debouncedPushHtmlChange = () => {};
  // jsdom has no insertText command; the helper falls back to setting the value.
  document.execCommand = () => false;

  e._insertImageByUrl("/a.png", "a", null);

  assert.equal(ta.value, 'before <img src="/a.png" alt="a" />after');
  ta.remove();
  e.cleanup();
});

test("markdown mode inserts the markdown form", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "markdown");
  const got = [];
  window["markdownEditorInsert_test_editor_markdown"] = (s) => got.push(s);

  e._insertImageByUrl("/a.png", "alt", null);

  assert.deepEqual(got, ["![alt](/a.png)"]);
  delete window["markdownEditorInsert_test_editor_markdown"];
  e.cleanup();
});

test("the host's insert_image follows the mode", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "markdown");
  const got = [];
  window["markdownEditorInsert_test_editor_markdown"] = (s) => got.push(s);

  e._handleCommand({ action: "insert_image", url: "/b.png", alt: "b" });

  assert.deepEqual(got, ["![b](/b.png)"]);

  e._insertImageByUrl = () => got.push("refused");
  e._handleCommand({ action: "insert_image", url: "javascript:alert(1)", alt: "b" });
  assert.deepEqual(got, ["![b](/b.png)"], "a URL that runs code is not inserted anywhere");

  delete window["markdownEditorInsert_test_editor_markdown"];
  e.cleanup();
});
