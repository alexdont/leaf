"use strict";

// A real DOM for the tests that need one.
//
// The stubbed tests alongside these cover the parts of the bundle that are
// pure state. They cannot cover the editor's DOM work, and the difference is
// not academic: three separate list/undo defects shipped past a green stubbed
// suite because a stub cannot tell "has a child node" from "has text", and
// cannot run a keydown handler at all.
//
// jsdom is a devDependency (see ../../package.json) and deliberately not
// required to use leaf — the shipped bundle has no dependencies. When it is
// missing, `available` is false and the DOM tests skip with a message rather
// than failing, so `mix test` still passes on a machine that never ran
// `npm install`.

let JSDOM = null;

try {
  ({ JSDOM } = require("jsdom"));
} catch (_) {
  // Left null; callers skip.
}

const available = JSDOM !== null;
const skip = available ? false : "jsdom not installed — run `npm install` in the leaf checkout";

const ZWSP = "​";

let proto = null;

// Build the window the bundle expects, load it, and hand back the hook object.
// Done once: the bundle registers onto `window` at load and is not re-entrant.
function hook() {
  if (proto) return proto;

  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    pretendToBeVisual: true,
  });

  global.window = dom.window;
  global.document = dom.window.document;
  global.Node = dom.window.Node;
  global.Range = dom.window.Range;
  global.NodeFilter = dom.window.NodeFilter;
  global.Event = dom.window.Event;
  global.KeyboardEvent = dom.window.KeyboardEvent;
  global.getComputedStyle = dom.window.getComputedStyle.bind(dom.window);
  if (!global.navigator) global.navigator = dom.window.navigator;

  dom.window.LeafHooks = dom.window.LeafHooks || {};
  require("../../../priv/static/assets/leaf.js");

  proto = dom.window.LeafHooks.Leaf;
  return proto;
}

// An editor instance over `html`, with everything the handlers reach for that
// is not under test stubbed to a no-op. Anything a test cares about it should
// override on the returned object.
function editor(html, mode = "visual") {
  const base = hook();
  const host = document.createElement("div");

  host.setAttribute("contenteditable", "true");
  host.innerHTML = html;
  document.body.appendChild(host);

  const e = Object.create(base);
  const noop = () => {};

  Object.assign(e, {
    _visualEl: host,
    el: host,
    _mode: mode,
    _readonly: false,
    _editorId: "test-editor",
    _debounceMs: 0,
    _syntaxMutating: false,
    _sourceBlock: null,
    _lastSourceStateKey: null,
    _activeMatchKey: null,
    pushEventTo: noop,
    _syncFormInput: noop,
    _computeDirty: () => false,
    _suggestKeydown: () => false,
    _historyKeydown: () => false,
    _historyCapture: noop,
    _historyCaptureNow: noop,
    _selectionCoversAllContent: () => false,
    _debouncedPushVisualChange: noop,
    _updateToolbarState: noop,
    _updateSourceBlock: noop,
    _updateCounts: noop,
    _deferredSyntaxRefresh: noop,
    _refreshSourceBlock: noop,
    _snapshotFormattingElements: () => new Set(),
    _inlineFormattingAncestor: () => null,
    _maybeHandleSourceDelete: () => false,
    _dismissLinkPopover: noop,
    _suggestClose: noop,
    _suggestScan: noop,
  });

  e.cleanup = () => host.remove();
  return e;
}

// Put the caret at the end of `node`'s text.
function caretAtEndOf(node) {
  const text = node.firstChild && node.firstChild.nodeType === 3 ? node.firstChild : node;
  const range = document.createRange();

  range.setStart(text, text.nodeType === 3 ? text.textContent.length : 0);
  range.collapse(true);

  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  return range;
}

function pressEnter(e) {
  const event = new window.KeyboardEvent("keydown", {
    key: "Enter",
    bubbles: true,
    cancelable: true,
  });

  e._onVisualKeydown(event);
  return event;
}

// The markup, with zero-width placeholders made visible so a failure message
// shows where they are.
function readable(el) {
  return el.innerHTML.split(ZWSP).join("[zwsp]");
}

module.exports = { available, skip, hook, editor, caretAtEndOf, pressEnter, readable, ZWSP };
