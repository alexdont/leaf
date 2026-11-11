"use strict";

// Mention tokens — `@[type:id|Label]` / `#[type:id|Label]` — as chips.
//
// The token is the host's (phoenix_kit's mention grammar); Leaf only shows it
// as "@Label" and writes it back byte for byte. Visual mode used to escape its
// `[` on the way back to markdown (`@\[user:…]`), which turned a mention into
// text.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

const ADA = "01a0306e-577c-790e-971a-4e8dee4d3200";
const Q3 = "018e3c4a-9f6b-7890-abcd-ef1234567891";
const PERSON = `@[user:${ADA}|Ada Lovelace]`;
const RECORD = `#[project_task:${Q3}|Q3 launch]`;

function mentionEditor(html, mode = "visual", on = true) {
  const e = editor(html || "<p>x</p>", mode);
  e._mentions = on;
  e._hashtags = true;
  e._wikiLinks = true;
  e._mode = mode;
  return e;
}

function decorate(e, text) {
  const box = document.createElement("div");
  e._textWithDecorations(text).forEach((n) => box.appendChild(n));
  return box;
}

test("a person and a record read as chips", { skip }, () => {
  const e = mentionEditor();
  const box = decorate(e, `Hi ${PERSON}, see ${RECORD}.`);
  const chips = box.querySelectorAll(".leaf-mention");

  assert.equal(chips.length, 2);
  assert.equal(chips[0].textContent, "@Ada Lovelace");
  assert.equal(chips[0].getAttribute("data-leaf-mention-raw"), PERSON);
  assert.equal(chips[0].getAttribute("contenteditable"), "false");
  assert.equal(chips[1].textContent, "#Q3 launch");
  // A record token is not a hashtag.
  assert.equal(box.querySelector(".leaf-hashtag"), null);
  assert.equal(box.textContent, "Hi @Ada Lovelace, see #Q3 launch.");
  e.cleanup();
});

test("off unless the host turns mentions on", { skip }, () => {
  const e = mentionEditor(null, "visual", false);
  assert.equal(decorate(e, `Hi ${PERSON}`).querySelector(".leaf-mention"), null);
  e.cleanup();
});

test("anything short of a token, or an escaped one, stays text", { skip }, () => {
  const e = mentionEditor();
  for (const text of ["@[user:nope|Ada]", `@[user:${ADA}]`, `@[user:${ADA}|Ada`, `\\${PERSON}`]) {
    assert.equal(decorate(e, text).querySelector(".leaf-mention"), null, text);
  }
  e.cleanup();
});

test("visual mode writes the token back unescaped", { skip }, () => {
  const e = mentionEditor(
    `<p>Hi <span class="leaf-mention" contenteditable="false" data-leaf-mention-raw="${PERSON}">@Ada Lovelace</span> there</p>`
  );
  assert.equal(e._currentMarkdown().trim(), `Hi ${PERSON} there`);
  e.cleanup();
});

test("a hybrid block renders its mentions as chips", { skip }, () => {
  const e = mentionEditor("<p>x</p>", "hybrid");
  const block = e._renderBlockFromSource(`Hi ${PERSON} there`);
  const chip = block.querySelector(".leaf-mention");

  assert.ok(chip, "chip rendered");
  assert.equal(chip.textContent, "@Ada Lovelace");
  assert.equal(chip.getAttribute("data-leaf-mention-raw"), PERSON);
  e.cleanup();
});

// The block being edited, in source form: the token reads "@Label" with
// `[user:…|` and `]` in markers (hidden by the CSS) until the caret is in it.
function sourceEditor(text) {
  const e = mentionEditor('<p data-leaf-source="p">' + text + "</p>", "hybrid");
  e._refreshSourceBlock = Object.getPrototypeOf(e)._refreshSourceBlock;
  e._sourceBlock = e._visualEl.firstChild;
  return e;
}

function caretAt(e, offset) {
  const walker = document.createTreeWalker(e._sourceBlock, window.NodeFilter.SHOW_TEXT);
  let left = offset;
  let node;
  while ((node = walker.nextNode())) {
    if (left <= node.textContent.length) break;
    left -= node.textContent.length;
  }
  const range = document.createRange();
  range.setStart(node, left);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}

test("in source form a mention is its label until the caret enters it", { skip }, () => {
  const source = `Hi ${PERSON} there`;
  const e = sourceEditor(source);

  caretAt(e, source.length);
  e._refreshSourceBlock();
  let chip = e._sourceBlock.querySelector(".leaf-mention");
  assert.ok(chip, "chip in source form");
  const markers = [...chip.querySelectorAll(".leaf-source-marker")].map((m) => m.textContent);
  assert.deepEqual(markers, [`[user:${ADA}|`, "]"]);
  assert.ok(!chip.classList.contains("leaf-source-active"));
  assert.equal(e._serializeBlockInline(e._sourceBlock).source, source);

  caretAt(e, "Hi @[us".length);
  e._refreshSourceBlock();
  chip = e._sourceBlock.querySelector(".leaf-mention");
  assert.ok(chip.classList.contains("leaf-source-active"), "caret inside reveals the source");
  assert.equal(e._serializeBlockInline(e._sourceBlock).source, source);
  e.cleanup();
});

test("a picked mention becomes its chip where it landed, caret after it", { skip }, () => {
  const e = mentionEditor("<p>Hi </p>");
  const p = e._visualEl.querySelector("p");
  const text = p.firstChild;
  text.textContent = `Hi ${PERSON} and more`;

  const sel = window.getSelection();
  const range = document.createRange();
  const caret = `Hi ${PERSON} `.length;
  range.setStart(text, caret);
  range.collapse(true);
  sel.removeAllRanges();
  sel.addRange(range);

  e._chipMentionsIn(text);

  const chip = p.querySelector(".leaf-mention");
  assert.ok(chip, "chip made");
  assert.equal(p.textContent, "Hi @Ada Lovelace and more");
  // The caret is still right after the pick's trailing space.
  const at = window.getSelection().getRangeAt(0);
  assert.equal(at.startContainer.textContent, " and more");
  assert.equal(at.startOffset, 1);
  assert.equal(e._currentMarkdown().trim(), `Hi ${PERSON} and more`);
  e.cleanup();
});
