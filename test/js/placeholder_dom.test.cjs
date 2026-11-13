"use strict";

// The placeholder shows on an empty editor. An empty editor holds a
// `<p><br></p>`, which `:empty` never matched, so it used to show nowhere.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

const empty = (html) => {
  const e = dom.editor(html, "hybrid");
  e._syncEmptyState();
  const on = e._visualEl.classList.contains("leaf-empty");
  e.cleanup();
  return on;
};

test("empty blocks read as empty", { skip: dom.skip }, () => {
  assert.equal(empty("<p><br></p>"), true);
  assert.equal(empty(""), true);
  assert.equal(empty("<p>​</p>"), true);
});

test("text or media is not empty", { skip: dom.skip }, () => {
  assert.equal(empty("<p>x</p>"), false);
  assert.equal(empty('<p><img src="/a.png"></p>'), false);
  assert.equal(empty("<hr>"), false);
});

test("typing clears it, deleting brings it back", { skip: dom.skip }, () => {
  const e = dom.editor("<p><br></p>", "hybrid");
  e._syncEmptyState();
  assert.ok(e._visualEl.classList.contains("leaf-empty"));
  e._visualEl.firstChild.textContent = "hi";
  e._syncEmptyState();
  assert.ok(!e._visualEl.classList.contains("leaf-empty"));
  e._visualEl.innerHTML = "<p><br></p>";
  e._syncEmptyState();
  assert.ok(e._visualEl.classList.contains("leaf-empty"));
  e.cleanup();
});
