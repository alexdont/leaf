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
global.Node = { ELEMENT_NODE: 1, TEXT_NODE: 3 };
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
  // A nested list, an image, a <br> or a checkbox all render on their own;
  // adding a placeholder would put a stray text node before them. A task BOX
  // is deliberately not in this list — see the task-item case below.
  for (const child of ["ul", "ol", "img", "br", "input"]) {
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

// ---------------------------------------------------------------------------
// Enter on an empty item: continue mid-list, exit only at the end.
// ---------------------------------------------------------------------------

const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

function node(type, text = "") {
  return { nodeType: type, textContent: text, nextSibling: null };
}

function chain(nodes) {
  nodes.forEach((n, i) => (n.nextSibling = nodes[i + 1] || null));
  return nodes;
}

test("an item followed by another item is mid-list", () => {
  // Enter here must continue the list, not exit it.
  const [first, second] = chain([node(ELEMENT_NODE), node(ELEMENT_NODE)]);

  assert.equal(proto._nextListSibling(first), second);
});

test("the last item has no following sibling", () => {
  const last = node(ELEMENT_NODE);

  assert.equal(proto._nextListSibling(last), null);
});

test("whitespace between items does not make the last item look mid-list", () => {
  // Pretty-printed server HTML leaves text nodes between <li>s, and the
  // stripper only runs on synced content. Counting one as "something follows"
  // would stop Enter ever exiting a list.
  const first = node(ELEMENT_NODE);
  const gap = node(TEXT_NODE, "\n  ");
  chain([first, gap]);

  assert.equal(proto._nextListSibling(first), null);
});

test("meaningful text after an item does count", () => {
  const first = node(ELEMENT_NODE);
  const stray = node(TEXT_NODE, "trailing text");
  chain([first, stray]);

  assert.equal(proto._nextListSibling(first), stray);
});

test("whitespace before a real item is skipped, not mistaken for the end", () => {
  const first = node(ELEMENT_NODE);
  const gap = node(TEXT_NODE, "\n");
  const second = node(ELEMENT_NODE);
  chain([first, gap, second]);

  assert.equal(proto._nextListSibling(first), second);
});

test("a null item is a no-op rather than a throw", () => {
  assert.equal(proto._nextListSibling(null), null);
});


// ---------------------------------------------------------------------------
// The single-item form, and the defect that made every new bullet invisible.
// ---------------------------------------------------------------------------

test("an item holding a child but no text still gets a placeholder", () => {
  // The real shape: `Range.extractContents()` hands back a fragment containing
  // an EMPTY TEXT NODE when the caret sat at the end of a line. The old check
  // was `!newLi.firstChild`, which such an item passes — so splitting at the
  // end of a bullet, the ordinary way to make the next one, produced an item
  // that had a child, reported itself occupied, and rendered at zero height.
  // Invisible from birth, not cleared later.
  const item = li("", []);
  item.firstChild = { nodeType: 3, textContent: "" };

  proto._ensureListItemPlaceholder(item);

  assert.equal(item._appended.length, 1);
});

test("the single-item form reports whether it did anything", () => {
  assert.equal(proto._ensureListItemPlaceholder(li("")), true);
  assert.equal(proto._ensureListItemPlaceholder(li("text")), false);
  assert.equal(proto._ensureListItemPlaceholder(null), false);
});

test("an empty task item gets a caret home despite its checkbox", () => {
  // The box is not content: without a text node the label has nowhere to be
  // typed and the caret nowhere to sit.
  const item = li("", [".leaf-task-box"]);

  proto._ensureListItemPlaceholder(item);

  assert.equal(item._appended.length, 1);
});

// ---------------------------------------------------------------------------
// Hybrid mode: leaving an empty item.
//
// The reported bug lived here, not in the visual editor. Hybrid re-renders a
// block from its markdown source when the caret leaves it, and that path
// DELETED an empty list item outright — "visual noise", per its comment. True
// for a trailing bullet somebody abandoned; wrong for a blank row deliberately
// left inside a list, which vanished the moment the caret moved away.
// ---------------------------------------------------------------------------

function sourceLi(markerText) {
  return {
    // nodeType matters: `_nextListSibling` walks siblings element-wise, so a
    // stub without it reads as "nothing follows" and every item looks like the
    // last one in its list.
    nodeType: ELEMENT_NODE,
    textContent: markerText,
    nextSibling: null,
    getAttribute: (name) => (name === "data-leaf-source" ? "li" : null),
    hasAttribute: () => true,
  };
}

function listAround(items) {
  const list = {
    tagName: "UL",
    _removed: [],
    firstElementChild: items[0],
    parentNode: { removeChild: noop },
    removeChild(child) {
      this._removed.push(child);
    },
    replaceChild(fresh, old) {
      this._replaced = { fresh, old };
    },
  };
  items.forEach((item, i) => {
    item.parentNode = list;
    item.nextSibling = items[i + 1] || null;
  });
  return list;
}

function exiting() {
  const e = Object.create(proto);
  e._mode = "hybrid";
  e._syntaxMutating = false;
  e._renderListItemFromSource = () => ({ querySelector: () => null, textContent: "", _appended: [], appendChild(n) { this._appended.push(n); } });
  e._renderBlockFromSource = () => ({});
  e._exitListItemToParagraph = noop;
  e._ensureListItemPlaceholder = proto._ensureListItemPlaceholder;
  return e;
}

test("an empty item in the middle of a list survives the caret leaving", () => {
  const items = [sourceLi("- one"), sourceLi("- "), sourceLi("- three")];
  const list = listAround(items);
  const e = exiting();

  e._exitSourceMode(items[1]);

  assert.deepEqual(list._removed, [], "the middle item must not be dropped");
  assert.ok(list._replaced, "it should be re-rendered in place instead");
});

test("an empty item at the END of a list is still tidied away", () => {
  // A trailing bullet is the residue of starting an item and changing your
  // mind; clearing it is the point of the tidy-up.
  const items = [sourceLi("- one"), sourceLi("- ")];
  const list = listAround(items);
  const e = exiting();

  e._exitSourceMode(items[1]);

  assert.equal(list._removed.length, 1);
  assert.equal(list._removed[0], items[1]);
});

test("an item with content is never dropped, wherever it sits", () => {
  const items = [sourceLi("- one"), sourceLi("- two")];
  const list = listAround(items);
  const e = exiting();

  e._exitSourceMode(items[1]);

  assert.deepEqual(list._removed, []);
});
