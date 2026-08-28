"use strict";

// Collaboration has to cost nothing when it is not wanted.
//
// Plenty of people will use Leaf for a comment box or a content field and have
// no interest in any of this. If the machinery runs anyway — measuring
// coordinates, fingerprinting documents, listening for selection changes —
// they pay for a feature they never asked for.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

// Anything collaboration-only, replaced with something that fails loudly.
function forbidCollabWork(e) {
  const touched = [];

  for (const name of [
    "_visibleSegments",
    "_visibleText",
    "_visibleOffset",
    "_visibleNodeAt",
    "_digest",
    "_debugState",
    "_renderedSplice",
    "_rebaseOverPending",
    "_canFastPath",
  ]) {
    e[name] = () => {
      touched.push(name);
      throw new Error(`${name} ran with collaboration off`);
    };
  }

  return touched;
}

test("an edit does no collaboration work when it is off", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>", "hybrid");
  e._collabOperations = false;
  e._collabAwareness = false;
  e._collabDebug = false;

  const touched = forbidCollabWork(e);
  const sent = [];
  e.pushEventTo = (_el, name, payload) => sent.push([name, payload]);

  // The path every change goes through.
  e._scheduleOperation();
  e._emitOperation(e._currentMarkdown());
  e._emitAwareness();

  assert.deepEqual(touched, [], "nothing collaboration-only may run");
  assert.deepEqual(sent, [], "and nothing may be sent");

  e.cleanup();
});

test("no timer is left running when it is off", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>", "hybrid");
  e._collabOperations = false;

  e._scheduleOperation();

  assert.ok(!e._operationTimer, "an editor with no peers has nothing to schedule");

  e.cleanup();
});

test("turning it on is what starts the work", { skip: dom.skip }, () => {
  const e = dom.editor("<p>hello</p>", "hybrid");
  e._collabOperations = true;
  e._pending = [];
  e._lastSentMarkdown = "hello";
  e._currentMarkdown = () => "hello!";

  const sent = [];
  e.pushEventTo = (_el, name, payload) => sent.push([name, payload]);

  e._emitOperation(e._currentMarkdown());

  assert.equal(sent.length, 1, "the same call does something once asked for");
  assert.equal(sent[0][0], "operation");

  e.cleanup();
});
