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

// ALEX-134: inside code a paste is text; mid-line a paste splits the line.
const MD = "- a\n- b\n# not a heading";

function caretIn(node, offset) {
  const r = document.createRange();
  r.setStart(node, offset);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
}

test("a paste into a fenced code block is left to the browser as text", { skip: dom.skip }, () => {
  const e = withRender(dom.editor("<p>Before</p><pre><code>x = 1</code></pre><p>After</p>", "hybrid"), "<ul><li>a</li></ul>");
  caretIn(e._visualEl.querySelector("code").firstChild, 5);
  const ev = pasteText(e, MD);
  assert.ok(!ev.defaultPrevented, "native plain paste");
  assert.deepEqual(e.pushed, [], "nothing rendered");
  e.cleanup();
});

test("a paste into rendered inline code is text too", { skip: dom.skip }, () => {
  const e = withRender(dom.editor("<p>run <code>ls</code> now</p>", "visual"), "<ul><li>a</li></ul>");
  caretIn(e._visualEl.querySelector("code").firstChild, 2);
  assert.ok(!pasteText(e, MD).defaultPrevented);
  e.cleanup();
});

test("in a source block: inside backticks, or a typed fence, is code", { skip: dom.skip }, () => {
  for (const [html, at] of [["run `ls", 7], ["```\nx", 5]]) {
    const e = withRender(dom.editor(`<p data-leaf-source="p">${html}</p>`, "hybrid"), "<ul><li>a</li></ul>");
    e._sourceBlock = e._visualEl.firstChild;
    caretIn(e._sourceBlock.firstChild, at);
    assert.ok(!pasteText(e, MD).defaultPrevented, html);
    e.cleanup();
  }
  const e = withRender(dom.editor('<p data-leaf-source="p">run `ls` now</p>', "hybrid"), "<ul><li>a</li></ul>");
  e._sourceBlock = e._visualEl.firstChild;
  caretIn(e._sourceBlock.firstChild, 12);
  assert.ok(pasteText(e, "- a\n- b").defaultPrevented, "after a closed code span it is markdown again");
  e.cleanup();
});

test("mid-line in a rendered block: the line splits around the blocks", { skip: dom.skip }, () => {
  const e = withRender(dom.editor("<p>Hello world</p>", "visual"), "<ul><li>a</li><li>b</li></ul>");
  caretIn(e._visualEl.firstChild.firstChild, 6);
  pasteText(e, "- a\n- b");
  assert.equal(e._visualEl.innerHTML, "<p>Hello </p><ul><li>a</li><li>b</li></ul><p>world</p>");
  e.cleanup();
});

test("mid-line in a source block: split by its markdown text", { skip: dom.skip }, () => {
  const e = withRender(dom.editor('<p data-leaf-source="p">Hello **big** world</p>', "hybrid"), "<ul><li>a</li></ul>");
  e._sourceBlock = e._visualEl.firstChild;
  e._renderBlockFromSource = (src) => { const p = document.createElement("p"); p.textContent = "[" + src + "]"; return p; };
  caretIn(e._sourceBlock.firstChild, 13);
  pasteText(e, "- a\n- b");
  assert.equal(e._visualEl.innerHTML, "<p>[Hello **big**]</p><ul><li>a</li></ul><p>[world]</p>");
  assert.equal(e._sourceBlock, null, "the source block was replaced");
  e.cleanup();
});
