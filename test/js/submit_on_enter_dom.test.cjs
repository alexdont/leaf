"use strict";

// `submit_on_enter` (on by default with chrome={:minimal}): Enter sends the
// text to the host instead of splitting the block.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function editorWith(html, { submit = true, mode = "hybrid" } = {}) {
  const e = dom.editor(html, mode);
  e.el.dataset.submitOnEnter = submit ? "true" : "false";
  e.pushed = [];
  e.pushEventTo = (_el, name, payload) => e.pushed.push([name, payload]);
  return e;
}

function key(e, opts) {
  const event = new window.KeyboardEvent("keydown", Object.assign({ key: "Enter", bubbles: true, cancelable: true }, opts));
  e._onVisualKeydown(event);
  return event;
}

test("Enter flushes the content, then submits it", { skip: dom.skip }, () => {
  const e = editorWith("<p>Buy <strong>milk</strong></p>");
  dom.caretAtEndOf(e._visualEl.querySelector("strong"));
  const ev = key(e);

  assert.ok(ev.defaultPrevented);
  assert.deepEqual(e.pushed.map(([n]) => n), ["content_changed", "submit"]);
  const [, payload] = e.pushed[1];
  assert.equal(payload.editor_id, "test-editor");
  assert.equal(payload.markdown.trim(), "Buy **milk**");
  assert.match(payload.html, /<strong>milk<\/strong>/);
  assert.equal(e._visualEl.querySelectorAll("p").length, 1, "no new paragraph");
  e.cleanup();
});

test("an empty editor swallows Enter and sends nothing", { skip: dom.skip }, () => {
  const e = editorWith("<p><br></p>");
  dom.caretAtEndOf(e._visualEl.firstChild);
  const ev = key(e);
  assert.ok(ev.defaultPrevented);
  assert.deepEqual(e.pushed, []);
  e.cleanup();
});

test("Shift+Enter, modified Enter and an IME composition are not a submit", { skip: dom.skip }, () => {
  for (const opts of [{ shiftKey: true }, { ctrlKey: true }, { metaKey: true }, { altKey: true }, { isComposing: true }]) {
    const e = editorWith("<p>x</p>");
    dom.caretAtEndOf(e._visualEl.firstChild);
    assert.equal(e._maybeSubmit(new window.KeyboardEvent("keydown", Object.assign({ key: "Enter", cancelable: true }, opts))), false, JSON.stringify(opts));
    assert.ok(!e.pushed.some(([n]) => n === "submit"));
    e.cleanup();
  }
});

test("Enter in an open suggestion list picks the item instead", { skip: dom.skip }, () => {
  const e = editorWith("<p>@al</p>");
  e._suggestKeydown = (ev) => { ev.preventDefault(); return true; };
  key(e);
  assert.deepEqual(e.pushed, []);
  e.cleanup();
});

test("off by default: Enter is a new paragraph as before", { skip: dom.skip }, () => {
  const e = editorWith("<p>x</p>", { submit: false });
  assert.equal(e._maybeSubmit(new window.KeyboardEvent("keydown", { key: "Enter", cancelable: true })), false);
  e.cleanup();
});

test("a readonly editor never submits", { skip: dom.skip }, () => {
  const e = editorWith("<p>x</p>");
  e._readonly = true;
  assert.equal(e._maybeSubmit(new window.KeyboardEvent("keydown", { key: "Enter", cancelable: true })), false);
  e.cleanup();
});

test("markdown mode submits the textarea's text", { skip: dom.skip }, () => {
  const e = editorWith("<p>ignored</p>", { mode: "markdown" });
  const ta = document.createElement("textarea");
  ta.value = "- [ ] call *Bob*";
  e._getMarkdownTextarea = () => ta;
  assert.equal(e._maybeSubmit(new window.KeyboardEvent("keydown", { key: "Enter", cancelable: true })), true);
  const submit = e.pushed.find(([n]) => n === "submit")[1];
  assert.equal(submit.markdown, "- [ ] call *Bob*");
  assert.equal(submit.html, "");
  e.cleanup();
});
