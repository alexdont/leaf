"use strict";

// A picture dragged from the desktop onto the editor used to be swallowed:
// the drop was cancelled and nothing happened. It now goes the way a pasted
// picture does.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function dropping(files) {
  return {
    clientX: 0,
    clientY: 0,
    dataTransfer: { files, types: ["Files"] },
    preventDefault() {},
  };
}

test("a dropped image file is handed to the image flow", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>");
  const got = [];
  e._handlePastedImage = (f) => got.push(f);

  e._dropFiles(dropping([{ type: "text/plain", name: "a.txt" }, { type: "image/png", name: "a.png" }]));

  assert.deepEqual(got, [{ type: "image/png", name: "a.png" }]);
  e.cleanup();
});

test("no image among the files, nothing happens", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>");
  let called = 0;
  e._handlePastedImage = () => called++;

  e._dropFiles(dropping([{ type: "application/pdf", name: "a.pdf" }]));
  e._dropFiles(dropping([]));

  assert.equal(called, 0);
  e.cleanup();
});

test("deny: [:images] and readonly refuse the drop", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>");
  let called = 0;
  e._handlePastedImage = () => called++;

  e._denyImages = true;
  e._dropFiles(dropping([{ type: "image/png", name: "a.png" }]));
  e._denyImages = false;
  e._readonly = true;
  e._dropFiles(dropping([{ type: "image/png", name: "a.png" }]));

  assert.equal(called, 0);
  e.cleanup();
});

test("a file drag is recognised by its type list", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>");
  assert.equal(e._draggedFiles({ dataTransfer: { types: ["Files"] } }), true);
  assert.equal(e._draggedFiles({ dataTransfer: { types: ["text/html"] } }), false);
  assert.equal(e._draggedFiles({}), false);
  e.cleanup();
});
