"use strict";

// Typing just before a closing marker — `**bol|**`, `[[Bo|]]` — must keep
// the caret inside the run.
//
// `_refreshSourceBlock` snaps a caret that arrow-keys into an inactive run
// to just outside it, since the browser skips the hidden markers and would
// otherwise land on the body's edge. It recognised "just entered" by the
// active run's offsets changing — and typing inside the run changes them
// too, so the first character typed before `**` / `]]` threw the caret out
// and the second landed after the run: `[[Boe]]` came out `[[Bo]]e`.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function sourceEditor(text) {
  const e = dom.editor('<p data-leaf-source="p">' + text + "</p>", "hybrid");
  const proto = Object.getPrototypeOf(e);
  e._refreshSourceBlock = proto._refreshSourceBlock;
  e._wikiLinks = true;
  e._sourceBlock = e._visualEl.firstChild;
  return e;
}

// Put the caret at source offset `offset` of the source block.
function caretAt(e, offset) {
  const block = e._sourceBlock;
  const walker = document.createTreeWalker(block, window.NodeFilter.SHOW_TEXT);
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

// Insert `ch` at the caret the way the browser does, then refresh.
function type(e, ch) {
  const sel = window.getSelection();
  const node = sel.anchorNode;
  const offset = sel.anchorOffset;
  node.insertData(offset, ch);
  const range = document.createRange();
  range.setStart(node, offset + ch.length);
  range.collapse(true);
  sel.removeAllRanges();
  sel.addRange(range);
  e._refreshSourceBlock();
}

function caretOffset(e) {
  const sel = window.getSelection();
  return e._serializeBlockInline(e._sourceBlock, sel.anchorNode, sel.anchorOffset);
}

const CASES = [
  { name: "bold", text: "x **bol**", inside: 5, beforeCloser: 7, typed: "d", want: "x **bold**" },
  { name: "wiki link", text: "A [[Bo]]", inside: 5, beforeCloser: 6, typed: "e", want: "A [[Boe]]" },
];

for (const c of CASES) {
  test(`typing before the closer of a ${c.name} keeps the caret inside`, { skip: dom.skip }, () => {
    const e = sourceEditor(c.text);
    caretAt(e, c.inside);
    e._refreshSourceBlock();
    caretAt(e, c.beforeCloser);
    e._refreshSourceBlock();

    type(e, c.typed);
    let out = caretOffset(e);
    assert.equal(out.source, c.want);
    assert.equal(out.cursorOffset, c.beforeCloser + 1, "caret stays before the closer");

    // And the next character goes in too.
    type(e, c.typed);
    out = caretOffset(e);
    assert.equal(out.source, c.want.slice(0, c.beforeCloser + 1) + c.typed + c.want.slice(c.beforeCloser + 1));
    e.cleanup();
  });
}

test("arrowing onto a run's edge from outside still snaps past it", { skip: dom.skip }, () => {
  // The behaviour the snap exists for: a caret that lands on the body edge of
  // a run it was not in (no edit) is placed just outside the run.
  const e = sourceEditor("x **bold** y");
  caretAt(e, 11);
  e._refreshSourceBlock();
  caretAt(e, 8);
  e._refreshSourceBlock();

  assert.equal(caretOffset(e).cursorOffset, 10);
  e.cleanup();
});
