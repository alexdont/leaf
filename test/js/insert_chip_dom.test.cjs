"use strict";

// A tag inserted from the host (`send_update(Leaf, action: :insert_markdown)`)
// arrives with the finished chip when the server could draw one. The browser
// can only draw an approximation (no markdown renderer, and no way to turn a
// `file_uuid` into a picture), so the server's wins.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function run(e, payload) {
  const calls = [];
  document.execCommand = (cmd, _ui, value) => {
    calls.push([cmd, value]);
    return true;
  };
  e._handleCommand(payload);
  return calls;
}

test("the server's chip is inserted as is", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._preserveTags = ["image"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};

  const chip = '<span class="leaf-atomic" data-leaf-tag="Image"><img class="leaf-atomic-media" src="/f/1"></span>';
  const calls = run(e, {
    action: "insert_markdown",
    text: '\n<Image file_uuid="abc"/>\n',
    chip,
  });

  assert.deepEqual(calls, [["insertHTML", chip]]);

  e.cleanup();
});

test("without one the browser builds its own from a preserved tag", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  e._preserveTags = ["image"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};

  const calls = run(e, { action: "insert_markdown", text: '<Image src="/a.png" alt="A"/>' });

  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "insertHTML");
  assert.match(calls[0][1], /data-leaf-tag="Image"/);

  e.cleanup();
});

test("plain text is inserted as text", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "visual");
  e._preserveTags = ["image"];
  e._debouncedPushVisualChange = () => {};
  e._updateCounts = () => {};

  const calls = run(e, { action: "insert_markdown", text: "hello" });

  assert.deepEqual(calls, [["insertText", "hello"]]);

  e.cleanup();
});
