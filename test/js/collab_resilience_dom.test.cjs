"use strict";

// Three ways a collaborating editor could go quietly wrong: a caret that
// drifts after a peer's edit in a multi-paragraph document, a deferred
// resync that never happens, and a wiki link asked about on every render.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function caretIn(node, offset) {
  const r = document.createRange();
  r.setStart(node, offset);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
}

test("the caret stays on its character after a peer's edit in a later paragraph", { skip: dom.skip }, () => {
  const e = dom.editor("<p>abc</p><p>def</p><p>ghi</p>", "hybrid");
  const p3 = e._visualEl.children[2].firstChild;
  caretIn(p3, 1);

  e._applyRemoteToVisual({ html: "<p>abc</p><p>def</p><p>ghi</p>", content: "abc\n\ndef\n\nghi" });

  const r = window.getSelection().getRangeAt(0);
  assert.equal(r.startContainer.textContent, "ghi");
  assert.equal(r.startOffset, 1, "between g and h, not a character per paragraph later");
  e.cleanup();
});

test("a resync deferred behind unacknowledged edits is asked for anyway after a while", { skip: dom.skip }, async () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const pushed = [];
  e.pushEventTo = (_el, name, payload) => pushed.push([name, payload]);
  e._pending = [{ seq: 1 }];
  e._needsResync = true;
  e._resyncFallbackMs = 20;

  e._armResyncFallback();
  assert.deepEqual(pushed, [], "not yet");
  await new Promise((r) => setTimeout(r, 60));

  assert.deepEqual(pushed, [["resync", { editor_id: "test-editor" }]]);
  assert.equal(e._needsResync, false);
  e.cleanup();
});

test("an acknowledgement that drains the queue cancels the fallback", { skip: dom.skip }, async () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const pushed = [];
  e.pushEventTo = (_el, name) => pushed.push(name);
  e._pending = [{ seq: 1 }];
  e._needsResync = true;
  e._resyncFallbackMs = 20;
  e._armResyncFallback();

  e._forgetPendingThrough(1);
  assert.deepEqual(pushed, ["resync"], "asked once, on the ack");
  await new Promise((r) => setTimeout(r, 60));
  assert.deepEqual(pushed, ["resync"], "and not again from the timer");
  e.cleanup();
});

test("a wiki link the host did not answer for is not asked about again", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<p><span data-leaf-wikilink="Known">Known</span> <span data-leaf-wikilink="Ghost">Ghost</span></p>',
    "hybrid"
  );
  e._wikiLinks = true;
  e._wikiLinksResolve = true;
  const asked = [];
  e.pushEventTo = (_el, name, payload) => name === "resolve_links" && asked.push(payload.targets);

  e._resolveWikiLinks();
  assert.deepEqual(asked, [["Known", "Ghost"]]);

  e._onWikiLinkTargets({ seq: e._wikiLinkSeq, targets: { Known: { exists: true, href: "/k" } } });
  e._resolveWikiLinks();
  e._resolveWikiLinks();

  assert.deepEqual(asked, [["Known", "Ghost"]], "Ghost is remembered as unknown");
  assert.equal(
    e._visualEl.querySelector('[data-leaf-wikilink="Ghost"]').getAttribute("data-leaf-wikilink-exists"),
    "false"
  );
  e.cleanup();
});

test("the document is not serialized on every keystroke unless a form field needs it", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>");
  const push = Object.getPrototypeOf(e)._debouncedPushVisualChange;
  let synced = 0;
  e._syncFormInput = () => synced++;
  e._debounceMs = 100000;
  e._scheduleOperation = () => {};

  push.call(e);
  assert.equal(synced, 0);

  e._syncInputName = "post[body]";
  push.call(e);
  assert.equal(synced, 1);
  clearTimeout(e._debounceTimer);
  e.cleanup();
});
