"use strict";

// What comes off the clipboard from a web page is somebody else's markup.
// It is cleaned of anything that runs, and the deny list applies to it the
// same way it applies to the toolbar.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function paste(e, data) {
  const inserted = [];
  document.execCommand = (cmd, _ui, value) => {
    inserted.push([cmd, value]);
    return true;
  };

  const evt = {
    type: "paste",
    clipboardData: {
      items: [],
      files: [],
      getData: (kind) => data[kind] || "",
    },
    prevented: false,
    preventDefault() {
      this.prevented = true;
    },
  };
  e._onPaste(evt);
  return { evt, inserted };
}

test("handlers, embeds and javascript: links are stripped", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, {
    "text/html":
      '<p onmouseover="x()">x <a href="javascript:alert(1)" onclick="y()">j</a>' +
      '<iframe src="https://evil"></iframe><svg onload="z()"></svg>' +
      '<img src="https://ok/a.png" onerror="w()" srcset="a 1x"> <object data="x"></object></p>',
    "text/plain": "x j",
  });

  assert.deepEqual(inserted, [["insertHTML", 'x <a>j</a><img src="https://ok/a.png"> ']]);
  e.cleanup();
});

test("a pasted picture may be a data: image", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const png = "data:image/png;base64,iVBORw0KGgo=";
  const { inserted } = paste(e, { "text/html": `<p><img src="${png}"></p>`, "text/plain": "" });

  assert.deepEqual(inserted, [["insertHTML", `<img src="${png}">`]]);
  e.cleanup();
});

test("a page that runs code in an href cannot smuggle it in a form or button", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const { inserted } = paste(e, {
    "text/html": 'a <form action="x"><button formaction="javascript:1">b</button></form><a href="https://ok">k</a>',
    "text/plain": "a b k",
  });

  assert.equal(inserted.length, 1);
  const html = inserted[0][1];
  assert.ok(!/form|button|formaction/.test(html), html);
  assert.ok(html.includes('<a href="https://ok">k</a>'), html);
  e.cleanup();
});

test("deny: [:links] applies to a copied line too", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._denyLinks = true;
  const { inserted } = paste(e, {
    "text/html": '<p>see <a href="https://x.y">the docs</a></p>',
    "text/plain": "see the docs",
  });

  assert.deepEqual(inserted, [["insertHTML", "see the docs"]]);
  e.cleanup();
});

test("deny: [:images] applies to a copied line too", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._denyImages = true;
  const { inserted } = paste(e, {
    "text/html": '<p>a <img src="https://x.y/p.png"> b</p>',
    "text/plain": "a  b",
  });

  assert.deepEqual(inserted, [["insertHTML", "a  b"]]);
  e.cleanup();
});

test("deny: [:links] leaves a pasted bare URL as text", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "visual");
  e._denyLinks = true;
  const { evt, inserted } = paste(e, { "text/plain": "https://x.y/page" });

  assert.equal(evt.prevented, false, "the browser's plain-text paste runs");
  assert.deepEqual(inserted, []);
  e.cleanup();
});

test("without the deny a pasted bare URL still becomes a link", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "visual");
  const { evt, inserted } = paste(e, { "text/plain": "https://x.y/page" });

  assert.equal(evt.prevented, true);
  assert.deepEqual(inserted, [["insertHTML", '<a href="https://x.y/page">https://x.y/page</a>']]);
  e.cleanup();
});
