"use strict";

// The strings leaf.js draws itself arrive translated as `data-leaf-i18n` on
// the hook element, keyed by their English; without one the English shows.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

// Translations are page-wide (the last editor mounted wins), so a throwaway
// editor is mounted to load them — a stubbed editor cannot finish a real
// mount — and a fresh one is returned for the assertions.
function mountWith(json) {
  const loader = dom.editor("<p>x</p>", "visual");
  if (json != null) loader.el.dataset.leafI18n = json;
  try {
    Object.getPrototypeOf(loader).mounted.call(loader);
  } catch (_) {
    // Translations load first; what fails after that is the stub.
  }
  loader.cleanup();
  return dom.editor("<p>x</p>", "visual");
}

function blockMenuLabels(e, html) {
  e._visualEl.innerHTML = html;
  const block = e._visualEl.firstChild;
  if (!e._visualWrapper) {
    const wrapper = document.createElement("div");
    const handle = document.createElement("div");
    e._visualEl.parentNode.insertBefore(wrapper, e._visualEl);
    wrapper.appendChild(handle);
    wrapper.appendChild(e._visualEl);
    e._visualWrapper = wrapper;
    e._dragHandle = handle;
  }
  Object.getPrototypeOf(e)._openBlockMenu.call(e, block);
  const menu = document.querySelector(".leaf-block-menu");
  const labels = [...menu.querySelectorAll("button")].map((b) => b.textContent.trim());
  menu.remove();
  return labels;
}

test("a malformed attribute leaves the English", { skip: dom.skip }, () => {
  const e = mountWith("{not json");
  const labels = blockMenuLabels(e, "<table><tr><td>a</td></tr></table>");
  assert.ok(labels.includes("Delete"));
  e.cleanup();
});

test("a translated block menu keeps Duplicate and Delete for a table", { skip: dom.skip }, () => {
  const e = mountWith(JSON.stringify({ Duplicate: "Duplizieren", Delete: "Löschen", Text: "Text DE" }));
  const forTable = blockMenuLabels(e, "<table><tr><td>a</td></tr></table>");
  assert.deepEqual(forTable, ["Duplizieren", "Löschen"]);

  const forParagraph = blockMenuLabels(e, "<p>a</p>");
  assert.ok(forParagraph.includes("Text DE"), "translated conversion items are shown for a paragraph");
  e.cleanup();
});
