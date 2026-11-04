"use strict";

// A LiveView patch runs `updated()`. The collaboration state the editor
// keeps across patches — edits still in the air, the revision they were
// written against — has to survive it, or the next incoming operation is
// rebased against a document it was not written for.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function patched(e) {
  e._setupSuggestions = () => {};
  e.updated();
  return e;
}

test("updated() keeps the unacknowledged edits and the revision", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._pending = [{ seq: 4, rendered: null }];
  e._collabRevision = 9;
  e._collabIntervalMs = 25;
  e.el.dataset.collabRevision = "3";
  e.el.dataset.collabInterval = "40";

  patched(e);

  assert.deepEqual(e._pending, [{ seq: 4, rendered: null }]);
  assert.equal(e._collabRevision, 9);
  assert.equal(e._collabIntervalMs, 25);
  e.cleanup();
});

test("updated() still follows the flags a host may change", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e.el.dataset.denyLinks = "true";
  e.el.dataset.collabDebug = "true";

  patched(e);

  assert.equal(e._denyLinks, true);
  assert.equal(e._collabDebug, true);
  e.cleanup();
});

test("document listeners added through the editor go with it", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>");
  let calls = 0;
  e._listenDocument("mousedown", () => calls++);
  e._listenDocument("selectionchange", () => calls++);

  document.dispatchEvent(new window.Event("mousedown"));
  document.dispatchEvent(new window.Event("selectionchange"));
  assert.equal(calls, 2);

  e._unlistenDocument();
  document.dispatchEvent(new window.Event("mousedown"));
  document.dispatchEvent(new window.Event("selectionchange"));
  assert.equal(calls, 2, "nothing runs after the editor is gone");

  assert.ok(/_unlistenDocument\(\)/.test(Object.getPrototypeOf(e).destroyed.toString()), "destroyed() takes them down");
  e.cleanup();
});

test("the toolbar's menu closers and the source tracker are such listeners", { skip: dom.skip }, () => {
  const src = require("fs").readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");
  const anonymous = src.match(/document\.addEventListener\("(mousedown|selectionchange)", function/g) || [];
  assert.deepEqual(anonymous, [], "an anonymous document listener cannot be removed");
});
