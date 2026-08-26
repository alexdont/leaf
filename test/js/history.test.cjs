"use strict";

// The undo/redo state machine in priv/static/assets/leaf.js.
//
// Leaf owns its history because the browser's could not survive how this
// editor works — see the block comment above `_historyInit` in the bundle.
// That makes the stack real logic rather than a thin wrapper, and this file
// covers the part that is pure state: what a capture appends, what undo and
// redo walk to, and what truncates or resets it.
//
// The bundle is browser code (an IIFE assigning onto `window`), so the globals
// it touches at load time are stubbed. The DOM-facing halves — reading a
// surface, measuring a caret — are stubbed per-instance too, so the machine is
// exercised without a DOM.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const noop = () => {};

global.window = { LeafHooks: {} };
global.document = {
  addEventListener: noop,
  removeEventListener: noop,
  createElement: () => ({
    style: {},
    setAttribute: noop,
    appendChild: noop,
    classList: { add: noop, remove: noop, toggle: noop },
  }),
  head: { appendChild: noop },
  body: { appendChild: noop },
  querySelector: () => null,
  querySelectorAll: () => [],
  getElementById: () => null,
  execCommand: () => true,
};
// `navigator` is a read-only getter under `node --test`, so only define it
// where the runtime has not already provided one.
if (!global.navigator) global.navigator = { userAgent: "node" };
global.getComputedStyle = () => ({});

require("../../priv/static/assets/leaf.js");

const proto = global.window.LeafHooks.Leaf;

// An editor with the DOM swapped for a plain map of per-mode content and a
// caret, so the history calls are the only real code under test.
function editor(mode = "visual") {
  const e = Object.create(proto);

  e._mode = mode;
  e._readonly = false;
  e._surfaces = { visual: "", markdown: "", html: "" };
  e._sel = { start: 0, end: 0 };
  e.el = { querySelector: () => null, querySelectorAll: () => [] };

  const key = (m) => (m === "hybrid" ? "visual" : m);

  e._historySurface = function (m) {
    return { mode: m || this._mode };
  };
  e._historyRead = function (m) {
    return this._surfaces[key(m)];
  };
  e._historySelection = function () {
    return { ...this._sel };
  };
  e._historyRestoreSelection = function (entry) {
    this._sel = { ...(entry.selection || { start: 0, end: 0 }) };
  };
  e._historySetMode = function (m) {
    this._mode = m;
  };
  e._historyAfterApply = noop;
  e._updateToolbarState = noop;

  e._write = function (text) {
    this._surfaces[key(this._mode)] = text;
  };

  e._historyApply = function (entry) {
    this._historyRestoring = true;
    if (entry.mode !== this._mode) this._historySetMode(entry.mode);
    this._surfaces[key(entry.mode)] = entry.content;
    this._historyRestoreSelection(entry);
    this._historyRestoring = false;
    this._updateToolbarState();
  };

  e._historyInit();
  return e;
}

function type(e, ...steps) {
  steps.forEach((text) => {
    e._write(text);
    e._historyCaptureNow();
  });
}

test("undo walks back to the previous content", () => {
  const e = editor();
  type(e, "hello", "hello world");

  e._historyUndo();

  assert.equal(e._surfaces.visual, "hello");
});

test("redo walks forward again", () => {
  const e = editor();
  type(e, "hello", "hello world");

  e._historyUndo();
  e._historyRedo();

  assert.equal(e._surfaces.visual, "hello world");
});

test("undo stops at the opening state", () => {
  const e = editor();
  type(e, "a", "b");

  e._historyUndo();
  e._historyUndo();
  e._historyUndo();

  assert.equal(e._surfaces.visual, "");
  assert.equal(e._historyCanUndo(), false);
});

test("a fresh edit truncates the redo future", () => {
  const e = editor();
  type(e, "a", "b", "c");

  e._historyUndo();
  e._historyUndo();
  type(e, "z");

  assert.equal(e._historyCanRedo(), false);
  assert.equal(e._surfaces.visual, "z");
});

test("an unchanged capture does not append a duplicate", () => {
  // Toolbar actions capture before AND after, and a no-op action would
  // otherwise put two identical states on the stack — making the first undo
  // appear to do nothing.
  const e = editor();
  type(e, "same");

  e._historyCaptureNow();
  e._historyCaptureNow();

  assert.equal(e._history.length, 2);
});

test("an unchanged capture still refreshes the caret", () => {
  const e = editor();
  type(e, "same");

  e._sel = { start: 4, end: 4 };
  e._historyCaptureNow();

  assert.equal(e._history[e._historyIndex].selection.start, 4);
});

test("restoring does not capture the state being restored", () => {
  // Replacing content fires input events; capturing those would append the
  // state just undone and make undo look inert.
  const e = editor();
  type(e, "one", "two");
  const before = e._history.length;

  e._historyUndo();
  e._historyCapture("input");

  assert.equal(e._history.length, before);
});

test("the stack is capped, keeping the newest", () => {
  const e = editor();
  for (let i = 0; i < proto._HISTORY_LIMIT + 60; i++) type(e, "v" + i);

  assert.ok(e._history.length <= proto._HISTORY_LIMIT);
  assert.equal(
    e._history[e._history.length - 1].content,
    "v" + (proto._HISTORY_LIMIT + 59)
  );
});

test("undo crosses back into the mode the edit happened in", () => {
  // The content of a step only exists in the representation it was made in,
  // so returning to that mode is the only honest restore.
  const e = editor("visual");
  type(e, "<p>vis</p>");

  e._mode = "markdown";
  type(e, "# md");

  e._historyUndo();

  assert.equal(e._mode, "visual");
  assert.equal(e._surfaces.visual, "<p>vis</p>");
});

test("the caret travels with the entry", () => {
  const e = editor();
  e._write("abc");
  e._sel = { start: 3, end: 3 };
  e._historyCaptureNow();

  e._write("abcdef");
  e._sel = { start: 6, end: 6 };
  e._historyCaptureNow();

  e._historyUndo();

  assert.equal(e._sel.start, 3);
});

test("a reset drops the previous document's history", () => {
  // set_content replaces the document; its predecessor's steps are not
  // reachable from it, so undo must not resurrect replaced content.
  const e = editor();
  type(e, "old", "older still");

  e._historyReset();

  assert.equal(e._historyCanUndo(), false);
});

test("a readonly editor records nothing and undoes nothing", () => {
  const e = editor();
  e._readonly = true;
  const before = e._history.length;

  type(e, "x");

  assert.equal(e._history.length, before);
  assert.equal(e._historyUndo(), false);
});

test("the bundle never references an unbound `self`", () => {
  // Regression: the visual editor's history listener was written as
  // `function () { self._historyCapture("input"); }` inside `mounted()`, which
  // defines no `self`. Every keystroke threw a ReferenceError, so nothing was
  // ever captured — the undo button stayed greyed out while Ctrl+Z appeared to
  // work, because the undo path captures for itself before restoring.
  //
  // Nothing in the running editor surfaces such a throw: it happens inside a
  // DOM event listener, so it is swallowed into the console and the feature
  // just silently does nothing. A static check is the cheapest guard.
  const fs = require("node:fs");
  const path = require("node:path");

  const src = fs
    .readFileSync(path.join(__dirname, "../../priv/static/assets/leaf.js"), "utf8")
    .split("\n");

  // Top-level members of the hook object, plus `mounted()`, bound the scopes a
  // `var self = this` can live in.
  const blockStarts = src
    .map((line, i) => (/^    _?[a-zA-Z]+[:(]/.test(line) || line.trim() === "mounted() {" ? i : -1))
    .filter((i) => i >= 0);

  const offenders = [];

  src.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "");
    if (!/\bself\s*\./.test(code)) return;

    const start = blockStarts.filter((b) => b <= i).pop() ?? 0;
    const end = blockStarts.find((b) => b > i) ?? src.length;
    const block = src.slice(start, end).join("\n");

    if (!/\bself\s*=\s*this\b/.test(block)) {
      offenders.push(`line ${i + 1}: ${line.trim().slice(0, 70)}`);
    }
  });

  assert.deepEqual(
    offenders,
    [],
    "`self` used where no enclosing scope binds it:\n" + offenders.join("\n")
  );
});
