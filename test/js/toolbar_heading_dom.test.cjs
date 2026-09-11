"use strict";

// The toolbar heading button in hybrid mode edits the SOURCE TEXT — the
// same thing typing "## " does. formatBlock used to restyle the DOM while
// the text still read as a paragraph: pretty until the next exit
// re-rendered the block from its text and silently undid the click.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

function sourceEditor(text) {
  const e = editor("<p>x</p>", "hybrid");
  const block = document.createElement("p");
  block.setAttribute("data-leaf-source", "p");
  block.appendChild(document.createTextNode(text));
  e._visualEl.innerHTML = "";
  e._visualEl.appendChild(block);
  e._sourceBlock = block;

  const sel = window.getSelection();
  const r = document.createRange();
  r.setStart(block.firstChild, Math.min(4, text.length));
  r.collapse(true);
  sel.removeAllRanges();
  sel.addRange(r);
  return e;
}

function sourceText(e) {
  return e._sourceBlock.textContent.replace(/[​﻿]/g, "");
}

test("the heading button writes the marker into the source", { skip }, () => {
  const e = sourceEditor("header test");
  e._toggleHeading("h2");
  assert.ok(sourceText(e).startsWith("## header test"), sourceText(e));
  e.cleanup();
});

test("the same level toggles the marker back off", { skip }, () => {
  const e = sourceEditor("header test");
  e._toggleHeading("h2");
  e._toggleHeading("h2");
  assert.ok(sourceText(e).startsWith("header test"), sourceText(e));
  e.cleanup();
});

test("another level swaps the marker", { skip }, () => {
  const e = sourceEditor("header test");
  e._toggleHeading("h2");
  e._toggleHeading("h3");
  assert.ok(sourceText(e).startsWith("### header test"), sourceText(e));
  e.cleanup();
});
