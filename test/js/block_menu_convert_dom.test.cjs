"use strict";

// The block handle's "Text" / "Heading" / "Quote" used to pour a list's
// innerHTML into a <p>, which left <li> tags inside a paragraph. A list now
// becomes one block per item; a table or a rule has nothing to become.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

const LIST =
  '<ul><li>one<ul><li>deep</li></ul></li>' +
  '<li class="leaf-task" data-checked="true"><span class="leaf-task-box" contenteditable="false"></span>two <em>em</em></li></ul>';

test("a list becomes one paragraph per item, nested lists kept", { skip: dom.skip }, () => {
  const e = dom.editor(LIST);
  e._convertBlock(e._visualEl.firstChild, "p");

  assert.equal(e._visualEl.innerHTML, "<p>one</p><ul><li>deep</li></ul><p>two <em>em</em></p>");
  e.cleanup();
});

test("a list can become headings or a quote", { skip: dom.skip }, () => {
  const h = dom.editor("<ol><li>a</li><li>b</li></ol>");
  h._convertBlock(h._visualEl.firstChild, "h2");
  assert.equal(h._visualEl.innerHTML, "<h2>a</h2><h2>b</h2>");
  h.cleanup();

  const q = dom.editor("<ul><li>a</li></ul>");
  q._convertBlock(q._visualEl.firstChild, "blockquote");
  assert.equal(q._visualEl.innerHTML, "<blockquote><p>a</p></blockquote>");
  q.cleanup();
});

test("a table, a figure and a rule are left alone", { skip: dom.skip }, () => {
  for (const html of ["<table><tr><td>x</td></tr></table>", "<figure><img src=\"/a.png\"></figure>", "<hr>"]) {
    const e = dom.editor(html);
    e._convertBlock(e._visualEl.firstChild, "p");
    assert.equal(e._visualEl.innerHTML, html.replace(/<tr>/, "<tbody><tr>").replace(/<\/tr>/, "</tr></tbody>"), html);
    e.cleanup();
  }
});

test("a paragraph still converts as before", { skip: dom.skip }, () => {
  const e = dom.editor("<p>a <strong>b</strong></p>");
  e._convertBlock(e._visualEl.firstChild, "h1");
  assert.equal(e._visualEl.innerHTML, "<h1>a <strong>b</strong></h1>");
  e.cleanup();
});
