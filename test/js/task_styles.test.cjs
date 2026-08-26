"use strict";

// Styling of completed task items.
//
// Asserted against the stylesheet the bundle injects rather than a rendered
// page: jsdom does not lay out or paint, so a computed-style check here would
// prove less than reading the rules does.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const src = fs.readFileSync(
  path.join(__dirname, "../../priv/static/assets/leaf.js"),
  "utf8"
);

// The injected CSS is an array of string fragments; join them so a rule split
// across several entries still matches.
const css = src
  .split("\n")
  .filter((line) => /^\s*"\.content-editor-visual|^\s*"\s{2}/.test(line))
  .join(" ");

test("a checked item is struck through", () => {
  assert.match(
    css,
    /li\.leaf-task\[data-checked='true'\][^"]*",\s*"\s*opacity: 0\.65; text-decoration: line-through;/,
    "a completed item should read as done at a glance"
  );
});

test("a checked item stays muted as well as struck", () => {
  assert.match(css, /opacity: 0\.65; text-decoration: line-through/);
});

test("the line is suppressed while the item is being edited", () => {
  // In hybrid the block under the cursor shows its markdown source —
  // `- [x] label` — and striking through syntax you are editing is unreadable.
  assert.match(
    css,
    /li\.leaf-task\[data-checked='true'\]\[data-leaf-source\][^"]*",\s*"\s*text-decoration: none;/
  );
});

test("the checkbox is an atomic inline, so the line cannot cross it", () => {
  // Load-bearing, and easy to break by accident. CSS does not propagate
  // text-decoration into atomic inline-level boxes; that is the only reason
  // the line drawn by the <li> skips the tick instead of scoring through it.
  // Change `.leaf-task-box` to `display: inline` and the tick becomes
  // unreadable on every completed item.
  assert.match(
    css,
    /\.leaf-task-box[^"]*",\s*"\s*display: inline-block;/,
    ".leaf-task-box must stay display:inline-block"
  );
});
