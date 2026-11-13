"use strict";

// Issues from moving Pezu's task inputs to the minimal editor:
// ALEX-130 a pasted markdown list is drawn as blocks, ALEX-131 set_content
// keeps a trailing space.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function withRender(e, html) {
  e.pushed = [];
  e.pushEventTo = (_el, name, payload, reply) => { e.pushed.push([name, payload]); if (reply) reply({ html }); };
  e._normalizeRenderedHtml = () => {};
  e._ensureListItemPlaceholders = () => {};
  e._updateSourceBlock = () => {};
  return e;
}

function pasteText(e, text) {
  const ev = new window.Event("paste", { bubbles: true, cancelable: true });
  ev.clipboardData = { getData: (t) => (t === "text/plain" ? text : ""), items: [], files: [] };
  e._clipboardImageFile = () => null;
  e._maybePasteTabular = () => false;
  e._onPaste(ev);
  return ev;
}

const LIST = "- Book flights\n  - Compare prices\n- Renew passport";
const RENDERED = "<ul><li>Book flights<ul><li>Compare prices</li></ul></li><li>Renew passport</li></ul>";

test("a multi-line markdown paste is rendered by the server, not pasted as text", { skip: dom.skip }, () => {
  const e = withRender(dom.editor("<p><br></p>", "hybrid"), RENDERED);
  dom.caretAtEndOf(e._visualEl.firstChild);
  const ev = pasteText(e, LIST);

  assert.ok(ev.defaultPrevented);
  assert.deepEqual(e.pushed[0], ["render_paste", { text: LIST }]);
  assert.equal(e._visualEl.innerHTML, RENDERED, "the empty line is replaced by the blocks");
  const sel = window.getSelection();
  assert.equal(sel.anchorNode.textContent, "Renew passport", "caret at the end of the last item's text");
  assert.equal(sel.anchorOffset, "Renew passport".length);
  e.cleanup();
});

test("pasted at the end of a line, the blocks go after it", { skip: dom.skip }, () => {
  const e = withRender(dom.editor("<p>Plan:</p>", "hybrid"), "<ul><li>a</li><li>b</li></ul>");
  dom.caretAtEndOf(e._visualEl.firstChild);
  pasteText(e, "- a\n- b");
  assert.equal(e._visualEl.innerHTML, "<p>Plan:</p><ul><li>a</li><li>b</li></ul>");
  e.cleanup();
});

test("prose, one line, or no reply: not this path / pasted as text", { skip: dom.skip }, () => {
  const e = withRender(dom.editor("<p><br></p>", "hybrid"), "");
  dom.caretAtEndOf(e._visualEl.firstChild);
  assert.ok(!pasteText(e, "first line\nsecond line").defaultPrevented, "prose goes to the browser");
  assert.ok(!pasteText(e, "- one item").defaultPrevented, "a single line too");
  let inserted = null;
  const orig = document.execCommand;
  document.execCommand = (cmd, _ui, value) => { inserted = [cmd, value]; return true; };
  try { pasteText(e, LIST); } finally { document.execCommand = orig; }
  assert.deepEqual(inserted, ["insertText", LIST], "an empty reply pastes the text");
  e.cleanup();
});

test("set_content keeps the trailing space as a no-break space", { skip: dom.skip }, () => {
  const e = dom.editor("<p>Laev:</p>", "hybrid");
  e._keepTrailingSpaces("Laev: ");
  assert.equal(e._visualEl.innerHTML, "<p>Laev:&nbsp;</p>");
  e._keepTrailingSpaces("Laev:  ");
  assert.equal(e._visualEl.firstChild.textContent, "Laev:  ");
  e.cleanup();
});

test("no trailing space, or only spaces: nothing changes", { skip: dom.skip }, () => {
  const e = dom.editor("<p>Laev:</p>", "hybrid");
  e._keepTrailingSpaces("Laev:");
  e._keepTrailingSpaces("   ");
  assert.equal(e._visualEl.innerHTML, "<p>Laev:</p>");
  e.cleanup();
});

test("_placeCaretAtEdge lands inside the last text, not after the block", { skip: dom.skip }, () => {
  const e = dom.editor("<p>Laev:&nbsp;</p>", "hybrid");
  e._placeCaretAtEdge(e._visualEl, true);
  const sel = window.getSelection();
  assert.equal(sel.anchorNode.nodeType, 3);
  assert.equal(sel.anchorOffset, 6);
  e._placeCaretAtEdge(e._visualEl, false);
  assert.equal(window.getSelection().anchorOffset, 0);
  e._visualEl.innerHTML = "<p><br></p>";
  e._placeCaretAtEdge(e._visualEl, true);
  assert.equal(window.getSelection().anchorNode, e._visualEl.firstChild, "an empty block: in front of its <br>");
  e.cleanup();
});
