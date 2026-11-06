"use strict";

// The counters under the editor ("3 words · 12 chars · 1 min read") are
// translated like the rest of the browser's strings. English keeps singular
// and plural; a translation words them so one form fits every number.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function counted(text, translations) {
  if (translations) {
    const loader = dom.editor("<p>x</p>", "visual");
    loader.el.dataset.leafI18n = JSON.stringify(translations);
    try {
      Object.getPrototypeOf(loader).mounted.call(loader);
    } catch (_) {
      // Translations load first; what fails after is the stub.
    }
    loader.cleanup();
  }

  // Markdown mode reads a textarea's value; jsdom has no innerText for the
  // other modes, and the counting is the same.
  const e = dom.editor("<p></p>", "markdown");
  e._getMarkdownTextarea = () => ({ value: text });
  const footer = document.createElement("div");
  footer.innerHTML =
    "<span data-word-count></span><span data-char-count></span><span data-reading-time></span>";
  document.body.appendChild(footer);
  e._wordCountEl = footer.querySelector("[data-word-count]");
  e._charCountEl = footer.querySelector("[data-char-count]");
  e._readingTimeEl = footer.querySelector("[data-reading-time]");
  Object.getPrototypeOf(e)._updateCounts.call(e);
  const out = [e._wordCountEl, e._charCountEl, e._readingTimeEl].map((el) => el.textContent);
  footer.remove();
  e.cleanup();
  return out;
}

test("English: singular and plural", { skip: dom.skip }, () => {
  assert.deepEqual(counted("one"), ["1 word", "3 chars", "1 min read"]);
  assert.deepEqual(counted("two words"), ["2 words", "9 chars", "1 min read"]);
});

// Last: the translations are page-wide once loaded.
test("a translation is used for every count", { skip: dom.skip }, () => {
  const ru = {
    "{count} word": "Слов: {count}",
    "{count} words": "Слов: {count}",
    "{count} char": "Символов: {count}",
    "{count} chars": "Символов: {count}",
    "{count} min read": "{count} мин чтения",
  };

  assert.deepEqual(counted("one", ru), ["Слов: 1", "Символов: 3", "1 мин чтения"]);
  assert.deepEqual(counted("two words"), ["Слов: 2", "Символов: 9", "1 мин чтения"]);
});
