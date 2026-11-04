"use strict";

// The bundle is parsed whole: one construct an older engine rejects takes
// the editor down with it. Safari before 16.4 has no regex lookbehind.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

test("no regex lookbehind in the bundle", () => {
  const found = src.match(/\(\?<[=!]/g) || [];
  assert.deepEqual(found, []);
});
