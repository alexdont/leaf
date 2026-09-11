"use strict";

// A hand-typed preserved tag becomes its atomic chip when the cursor
// leaves the line — the same pretty form a full page reload produces.
// Before this, only the toolbar's insert path built chips live; a typed
// <Embed ... /> sat as raw text until someone refreshed the page.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

function chipEditor() {
  const e = editor("<p>x</p>", "hybrid");
  e._preserveTags = ["embed", "hero"];
  return e;
}

test("a typed self-closing tag exits to its chip", { skip }, () => {
  const e = chipEditor();
  const block = e._renderBlockFromSource('<Embed src="/demos/leaf" title="Try it" />');

  const chip = block.querySelector(".leaf-atomic");
  assert.ok(chip, "atomic chip rendered");
  assert.equal(chip.getAttribute("contenteditable"), "false");
  assert.equal(
    chip.getAttribute("data-leaf-raw"),
    '<Embed src="/demos/leaf" title="Try it" />',
    "the verbatim source rides the chip for serialization"
  );
  e.cleanup();
});

test("a typed block-form tag exits to its chip", { skip }, () => {
  const e = chipEditor();
  const block = e._renderBlockFromSource("<Hero title=\"Hi\">body words</Hero>");

  assert.ok(block.querySelector(".leaf-atomic"), "atomic chip rendered");
  e.cleanup();
});

test("an unlisted tag stays plain text", { skip }, () => {
  const e = chipEditor();
  const block = e._renderBlockFromSource('<Widget src="/x" />');

  assert.equal(block.querySelector(".leaf-atomic"), null);
  assert.ok(block.textContent.includes("<Widget"), "raw text preserved");
  e.cleanup();
});

test("prose around a tag stays a normal paragraph", { skip }, () => {
  const e = chipEditor();
  const block = e._renderBlockFromSource('before <Embed src="/x" /> after');

  // Only an exactly-one-tag block chips; mixed rows keep their text.
  assert.equal(block.querySelector(".leaf-atomic"), null);
  e.cleanup();
});
