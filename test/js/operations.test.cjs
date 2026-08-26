"use strict";

// Turning snapshots into operations.
//
// Leaf's wire contract is a snapshot: the whole markdown after a debounce. Two
// concurrent snapshots cannot be merged — from a before and an after you cannot
// tell an insert from a delete from a rewrite. `_spliceBetween` recovers the
// edit, which is what a host needs to merge two people's changes.
//
// Pure string logic, so no DOM: trim the common prefix, then the common suffix,
// and what remains in the middle is the edit.
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
const splice = (a, b) => proto._spliceBetween(a, b);

// Applying a splice is the host's job; doing it here proves the splice
// actually describes the change rather than merely looking plausible.
function apply(text, s) {
  return text.slice(0, s.at) + s.insert + text.slice(s.at + s.remove);
}

describeRoundTrip();

function describeRoundTrip() {
  const CASES = [
    ["typing a character", "hello", "hello!"],
    ["typing in the middle", "hello world", "hello brave world"],
    ["typing at the start", "world", "hello world"],
    ["deleting a character", "hello!", "hello"],
    ["deleting from the middle", "hello brave world", "hello world"],
    ["replacing a selection", "hello world", "hello there"],
    ["clearing everything", "hello", ""],
    ["filling an empty document", "", "hello"],
    ["a multi-line edit", "one\ntwo\nthree", "one\ntwo and a half\nthree"],
    ["two distant changes collapse into one splice", "aaa bbb ccc", "xaa bbb ccx"],
    ["a repeated character is spliced minimally", "aaa", "aaaa"],
  ];

  for (const [label, before, after] of CASES) {
    test(label, () => {
      const s = splice(before, after);

      assert.ok(s, "expected a splice");
      assert.equal(apply(before, s), after, "the splice must reproduce the change");
    });
  }
}

test("no change produces no operation", () => {
  // An idle re-render must not emit; a document that did not change has no
  // edit to merge.
  assert.equal(splice("hello", "hello"), null);
  assert.equal(splice("", ""), null);
});

test("an insertion reports no removal", () => {
  const s = splice("hello", "hello world");

  assert.equal(s.remove, 0);
  assert.equal(s.insert, " world");
  assert.equal(s.at, 5);
});

test("a deletion reports no insertion", () => {
  const s = splice("hello world", "hello");

  assert.equal(s.insert, "");
  assert.equal(s.remove, 6);
  assert.equal(s.at, 5);
});

test("the splice is minimal, not the whole document", () => {
  // The point of an operation: two people editing different paragraphs must
  // produce splices that do not overlap.
  const before = "para one\n\npara two\n\npara three";
  const after = "para one\n\npara TWO\n\npara three";
  const s = splice(before, after);

  assert.equal(s.remove, 3);
  assert.equal(s.insert, "TWO");
  assert.ok(s.at > 10, "the splice should sit at the changed paragraph");
});

test("edits in different paragraphs do not overlap", () => {
  const base = "alpha\n\nbeta\n\ngamma";
  const first = splice(base, "alpha EDIT\n\nbeta\n\ngamma");
  const second = splice(base, "alpha\n\nbeta\n\ngamma EDIT");

  const firstEnd = first.at + first.remove;

  assert.ok(firstEnd <= second.at, "one person's edit must not span another's");
});

test("unicode is spliced by code unit consistently", () => {
  // `at` and `remove` are code-unit offsets, which is what String.slice uses;
  // a host applying them the same way round-trips.
  const before = "café";
  const after = "cafés";
  const s = splice(before, after);

  assert.equal(apply(before, s), after);
});

test("null and undefined are treated as empty", () => {
  assert.equal(apply("", splice(null, "hi")), "hi");
  assert.equal(splice(null, null), null);
});

// ---------------------------------------------------------------------------
// Emission.
//
// The property that makes the existing debounce harmless: the splice is
// computed against the last state SENT, not the last state seen. However many
// keystrokes the debounce swallowed, the splice still describes the whole
// distance from what the host last heard.
// ---------------------------------------------------------------------------

function emitter() {
  const e = Object.create(proto);

  e._collabOperations = true;
  e._editorId = "ed";
  e.el = {};
  e.sent = [];
  e.pushEventTo = (_el, event, payload) => e.sent.push({ event, payload });

  return e;
}

test("the first call establishes a baseline and emits nothing", () => {
  // There is no operation from "nothing known" to the opening document — the
  // host already has that.
  const e = emitter();

  e._emitOperation("hello");

  assert.equal(e.sent.length, 0);
});

test("a later change emits one operation", () => {
  const e = emitter();

  e._emitOperation("hello");
  e._emitOperation("hello world");

  assert.equal(e.sent.length, 1);
  assert.equal(e.sent[0].event, "operation");
  assert.equal(e.sent[0].payload.insert, " world");
  assert.equal(e.sent[0].payload.remove, 0);
});

test("coalesced keystrokes still describe the whole change", () => {
  // The debounce may swallow any number of intermediate states. Diffing
  // against what was SENT means the operation still covers all of them.
  const e = emitter();

  e._emitOperation("h");
  e._emitOperation("hello world");

  assert.equal(e.sent.length, 1);
  assert.equal(e.sent[0].payload.insert, "ello world");
});

test("an unchanged document emits nothing", () => {
  const e = emitter();

  e._emitOperation("hello");
  e._emitOperation("hello");
  e._emitOperation("hello");

  assert.equal(e.sent.length, 0);
});

test("operations are sequenced", () => {
  const e = emitter();

  e._emitOperation("a");
  e._emitOperation("ab");
  e._emitOperation("abc");

  assert.deepEqual(e.sent.map((s) => s.payload.seq), [1, 2]);
});

test("each operation carries the length it applies to", () => {
  // A host holding a document of a different length knows it has diverged,
  // rather than applying an offset that no longer means what it meant.
  const e = emitter();

  e._emitOperation("hello");
  e._emitOperation("hello world");

  assert.equal(e.sent[0].payload.base_length, 5);
});

test("applying every operation in order reproduces the document", () => {
  // The whole contract, end to end: a host that starts from the baseline and
  // applies what it receives ends up with what the editor holds.
  const e = emitter();
  const states = ["one", "one two", "one two three", "one three", "ONE three"];

  states.forEach((s) => e._emitOperation(s));

  let host = states[0];
  for (const { payload } of e.sent) {
    assert.equal(host.length, payload.base_length, "base length must match");
    host = host.slice(0, payload.at) + payload.insert + host.slice(payload.at + payload.remove);
  }

  assert.equal(host, states[states.length - 1]);
});

test("nothing is emitted when the host has not opted in", () => {
  const e = emitter();
  e._collabOperations = false;

  e._emitOperation("hello");
  e._emitOperation("hello world");

  assert.equal(e.sent.length, 0);
});
