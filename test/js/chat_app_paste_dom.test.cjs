"use strict";

// A copy from a chat app (Telegram Desktop) pastes as its text.
//
// Telegram Desktop puts a message on the clipboard twice: as text/plain, and
// as HTML that is nothing but lines — `<html><body>line<br>line…</body></html>`.
// Leaf took the HTML, and the rich path inserted the lines as they were: a
// list or a heading written in the message never became one, and the result
// differed from the same text pasted from a plain-text clipboard (and from
// markdown mode, which reads text/plain). HTML that is only lines is now
// handled as its plain text; HTML with real formatting keeps the rich path.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

const LIST = "New features\n  - Laser measure\n  - Polish:\n    - Boards open over the page.";
const TELEGRAM = "<html><body>" + LIST.split("\n").join("<br>") + "</body></html>";
const RENDERED = "<p>New features</p><ul><li>Laser measure</li><li>Polish:<ul><li>Boards open over the page.</li></ul></li></ul>";

function editor() {
  const e = dom.editor("<p><br></p>", "hybrid");
  e.pushed = [];
  e.pushEventTo = (_el, name, payload, reply) => { e.pushed.push([name, payload]); if (reply) reply({ html: RENDERED }); };
  e._normalizeRenderedHtml = () => {};
  e._ensureListItemPlaceholders = () => {};
  e._updateSourceBlock = () => {};
  e._clipboardImageFile = () => null;
  e._maybePasteTabular = () => false;
  dom.caretAtEndOf(e._visualEl.firstChild);
  return e;
}

function paste(e, data) {
  const inserted = [];
  const real = document.execCommand;
  const ev = new window.Event("paste", { bubbles: true, cancelable: true });
  ev.clipboardData = { getData: (t) => data[t] || "", items: [], files: [] };
  document.execCommand = (cmd, _ui, value) => { inserted.push([cmd, value]); return true; };
  try { e._onPaste(ev); } finally { document.execCommand = real; }
  return { ev, inserted };
}

test("Telegram's lines-only HTML pastes like its text: markdown becomes blocks", { skip: dom.skip }, () => {
  const e = editor();
  const { ev } = paste(e, { "text/html": TELEGRAM, "text/plain": LIST });

  assert.ok(ev.defaultPrevented);
  assert.deepEqual(e.pushed[0], ["render_paste", { text: LIST }], "rendered from the plain text");
  assert.equal(e._visualEl.innerHTML, RENDERED);
  e.cleanup();
});

test("a plain chat message keeps every line", { skip: dom.skip }, () => {
  const e = editor();
  const msg = "Hey, quick update.\nThe offline mode is done.\nPRs tomorrow & <soon>.";
  const { ev, inserted } = paste(e, { "text/html": "<html><body>" + msg.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").split("\n").join("<br>") + "</body></html>", "text/plain": msg });

  assert.ok(ev.defaultPrevented, "not left to the browser, which would paste the HTML");
  assert.equal(e.pushed.length, 0, "not markdown: nothing to render");
  assert.deepEqual(inserted, [
    ["insertHTML", "Hey, quick update."],
    ["insertParagraph", undefined],
    ["insertHTML", "The offline mode is done."],
    ["insertParagraph", undefined],
    ["insertHTML", "PRs tomorrow &amp; &lt;soon&gt;."]
  ], "one line each, escaped");
  e.cleanup();
});

test("spans that style nothing still count as plain lines", { skip: dom.skip }, () => {
  const e = editor();
  const html = '<meta charset="utf-8"><span style="color: rgb(0,0,0); font-family: Arial;">' + LIST.split("\n").join("<br>") + "</span>";
  paste(e, { "text/html": html, "text/plain": LIST });
  assert.deepEqual(e.pushed[0], ["render_paste", { text: LIST }]);
  e.cleanup();
});

test("real formatting keeps the rich path", { skip: dom.skip }, () => {
  for (const html of [
    "<p>Read the <b>docs</b></p>",
    'Read the <a href="https://example.com">docs</a>',
    '<span style="font-weight: 700">Bold</span><br>line',
    "<ul><li>one</li><li>two</li></ul>"
  ]) {
    const e = editor();
    paste(e, { "text/html": html, "text/plain": "Read the docs\n- one" });
    assert.equal(e.pushed.length, 0, "not sent to the markdown renderer: " + html);
    e.cleanup();
  }
});

test("lines-only HTML with no plain text beside it is still pasted", { skip: dom.skip }, () => {
  const e = editor();
  const { ev, inserted } = paste(e, { "text/html": "<html><body>one<br>two</body></html>" });
  assert.ok(ev.defaultPrevented);
  assert.ok(inserted.length > 0, "the HTML path took it");
  e.cleanup();
});
