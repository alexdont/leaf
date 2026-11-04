"use strict";

// Every place a URL the writer typed becomes an href or a src goes through
// `_safeUrl`. A link prompt that accepted `javascript:` put a script into the
// other collaborators' pages.

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
const link = (url) => proto._safeUrl(url, "link");
const image = (url) => proto._safeUrl(url, "image");

test("web, mail and phone links and relative paths pass", () => {
  for (const url of [
    "https://example.com/a?b=c#d",
    "http://example.com",
    "HTTPS://EXAMPLE.COM",
    "/docs/page",
    "docs/page.md",
    "../up",
    "#section",
    "?q=1",
    "mailto:a@b.c",
    "tel:+1555",
  ]) {
    assert.equal(link(url), url, url);
  }
});

test("anything that runs is refused", () => {
  for (const url of [
    "javascript:alert(1)",
    "JAVASCRIPT:alert(1)",
    "java\tscript:alert(1)",
    "java\nscript:alert(1)",
    "  javascript:alert(1)",
    "\u0001javascript:alert(1)",
    "vbscript:x",
    "data:text/html,<script>1</script>",
    "data:image/svg+xml,<svg onload=alert(1)>",
    "foo:bar",
  ]) {
    assert.equal(link(url), null, url);
    assert.equal(image(url), null, url);
  }
});

test("an image may be a data: picture, a link may not", () => {
  const png = "data:image/png;base64,iVBORw0KGgo=";
  assert.equal(image(png), png);
  assert.equal(link(png), null);
});

test("nothing is nothing", () => {
  assert.equal(link(""), null);
  assert.equal(link("   "), null);
  assert.equal(link(null), null);
  assert.equal(link(undefined), null);
  assert.equal(link(42), null);
});

test("surrounding whitespace is trimmed, the URL itself is kept as typed", () => {
  assert.equal(link("  https://x.y/a b  "), "https://x.y/a b");
});
