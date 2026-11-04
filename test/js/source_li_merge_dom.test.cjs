"use strict";

// Delete at the end of a source-form list item merges the next item in. The
// next item is in rendered form, and taking its text alone dropped its
// formatting: `- a` + Delete before `**b** c` gave `- ab c`.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function sourceLi(html) {
  const e = dom.editor(html, "hybrid");
  const proto = Object.getPrototypeOf(e);
  e._maybeHandleSourceDelete = proto._maybeHandleSourceDelete;
  e._refreshSourceBlock = proto._refreshSourceBlock;
  e._sourceBlock = e._visualEl.querySelector("[data-leaf-source]");
  const t = e._sourceBlock.firstChild;
  const r = document.createRange();
  r.setStart(t, t.length);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
  return e;
}

test("the merged item keeps its formatting as source", { skip: dom.skip }, () => {
  const e = sourceLi('<ul><li data-leaf-source="li">- a</li><li><strong>b</strong> <em>c</em></li></ul>');

  assert.equal(e._maybeHandleSourceDelete(false, false), true);
  assert.equal(e._sourceBlock.textContent, "- a**b** *c*");
  assert.equal(e._visualEl.querySelectorAll("li").length, 1);
  e.cleanup();
});

test("a quoted paragraph merges the same way", { skip: dom.skip }, () => {
  const e = sourceLi('<blockquote><p data-leaf-source="p">one</p><p>two <code>x</code></p></blockquote>');

  assert.equal(e._maybeHandleSourceDelete(false, false), true);
  assert.equal(e._sourceBlock.textContent, "onetwo `x`");
  e.cleanup();
});
