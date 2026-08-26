"use strict";

// Empty list items surviving the markdown round-trip.
//
// Reported as: make a bullet, press Enter for a second one, leave it empty,
// click away — the empty bullet vanishes. It was never actually deleted. An
// `<li>` with no content renders at zero height and gives the caret nowhere to
// sit, and Chrome hides its marker too, so it looks gone.
//
// The Enter-split path already dropped a ZWSP into a newly created item for
// exactly this reason, but that placeholder is a client-side artifact: it is
// stripped on the way out to markdown (correctly), so an item coming BACK from
// the server arrived bare. `_ensureListItemPlaceholders` closes that gap.
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
  createTextNode: (text) => ({ nodeType: 3, textContent: text }),
};
if (!global.navigator) global.navigator = { userAgent: "node" };
global.getComputedStyle = () => ({});

require("../../priv/static/assets/leaf.js");

const proto = global.window.LeafHooks.Leaf;

// A stand-in for one <li>. `contents` is what the item holds; a selector query
// reports whichever of the height-giving elements it contains.
function li(text, contains = []) {
  return {
    textContent: text,
    _children: contains,
    _appended: [],
    querySelector: (sel) =>
      contains.some((c) => sel.includes(c)) ? {} : null,
    appendChild(node) {
      this._appended.push(node);
      this.textContent += node.textContent;
    },
  };
}

function root(items) {
  return { querySelectorAll: (sel) => (sel === "li" ? items : []) };
}

const ZWSP = "​";

test("an empty item gets a caret home", () => {
  // The exact shape the server returns for `- ` : <li></li>
  const item = li("");

  proto._ensureListItemPlaceholders(root([item]));

  assert.equal(item._appended.length, 1);
  assert.equal(item._appended[0].textContent, ZWSP);
});

test("an item holding only whitespace is treated as empty", () => {
  const item = li("   \n  ");

  proto._ensureListItemPlaceholders(root([item]));

  assert.equal(item._appended.length, 1);
});

test("an item with text is left alone", () => {
  const item = li("one");

  proto._ensureListItemPlaceholders(root([item]));

  assert.equal(item._appended.length, 0);
});

test("repeated runs add exactly one placeholder", () => {
  // This runs on every sync. The first version tested emptiness AFTER
  // stripping zero-width characters, so an item holding only its own
  // placeholder read as empty and collected another every time — an invisible
  // run of them growing for as long as the document stayed open.
  const item = li("");

  proto._ensureListItemPlaceholders(root([item]));
  proto._ensureListItemPlaceholders(root([item]));
  proto._ensureListItemPlaceholders(root([item]));

  assert.equal(item._appended.length, 1);
});

test("an item that arrives with a placeholder is left alone", () => {
  const item = li(ZWSP);

  proto._ensureListItemPlaceholders(root([item]));

  assert.equal(item._appended.length, 0);
});

test("items with their own height are left alone", () => {
  // A nested list, an image, a <br> or a task box all render on their own;
  // adding a placeholder would put a stray text node before them.
  for (const child of ["ul", "ol", "img", "br", "input", ".leaf-task-box"]) {
    const item = li("", [child]);

    proto._ensureListItemPlaceholders(root([item]));

    assert.equal(item._appended.length, 0, `expected ${child} to be left alone`);
  }
});

test("the empty item in the middle of a list is the one fixed", () => {
  // The reported sequence: three items, the middle one deliberately blank.
  const items = [li("one"), li(""), li("three")];

  proto._ensureListItemPlaceholders(root(items));

  assert.equal(items[0]._appended.length, 0);
  assert.equal(items[1]._appended.length, 1);
  assert.equal(items[2]._appended.length, 0);
});

test("a missing root is a no-op rather than a throw", () => {
  assert.doesNotThrow(() => proto._ensureListItemPlaceholders(null));
});
