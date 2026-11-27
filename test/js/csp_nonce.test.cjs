"use strict";

// GitHub issue #9: Leaf under a nonce-based Content-Security-Policy.
//
//   - the <style> the bundle creates takes the page's nonce (cspNonce);
//   - with a `style_nonce`, the server sends the editor's inline styles as
//     `data-leaf-style`, and the hook applies them (applyDataStyles).
//
// Both are closure functions of the bundle, lifted from its source and run
// against a stand-in document, so every case states exactly what the page
// holds.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "../../priv/static/assets/leaf.js"), "utf8");

function lift(name) {
  const start = SRC.indexOf(`  function ${name}(`);
  assert.notEqual(start, -1, `${name} not found in leaf.js`);
  const end = SRC.indexOf("\n  }\n", start);
  return SRC.slice(start, end + 4);
}

// A page: `styles` / `scripts` are the nonces of the nonced <style> and
// <script> elements on it, `loader` the nonce of the <script> that loaded the
// bundle, `own` what the host put on window.LeafHooks.
function nonceOf({ styles = [], scripts = [], loader = "", own = {} }, kind) {
  const document = {
    querySelectorAll(sel) {
      const list = sel === "style[nonce]" ? styles : sel === "script[nonce]" ? scripts : [];
      return list.map(nonce => ({ nonce }));
    },
  };
  const window = { LeafHooks: own };
  const run = new Function("window", "document", "LOADER_NONCE",
    lift("cspNonce") + "\nreturn cspNonce(" + JSON.stringify(kind) + ");");
  return run(window, document, loader);
}

test("#9: the stylesheet the bundle creates is stamped with the nonce before it is inserted", () => {
  const body = lift("injectStyles");
  assert.match(body, /var nonce = cspNonce\("style"\);\s*if \(nonce\) style\.nonce = nonce;[\s\S]*appendChild\(style\)/);
});

test("#9: a page with separate nonces gives the style one, from the host's <style>", () => {
  assert.equal(nonceOf({ styles: ["STY"], scripts: ["SCR"], loader: "SCR" }, "style"), "STY");
});

test("#9: one nonce for both: the loading <script>'s, then any nonced element", () => {
  assert.equal(nonceOf({ scripts: ["N"], loader: "N" }, "style"), "N");
  assert.equal(nonceOf({ scripts: ["N"] }, "style"), "N", "bundled into app.js: no currentScript");
  assert.equal(nonceOf({ styles: ["", "S2"] }, "style"), "S2", "a hidden (empty) nonce is skipped");
});

test("#9: the host's own setting wins", () => {
  assert.equal(nonceOf({ styles: ["STY"], loader: "SCR", own: { styleNonce: "MINE" } }, "style"), "MINE");
});

test("#9: no nonce anywhere: nothing is set", () => {
  assert.equal(nonceOf({}, "style"), "");
});

test("#9: data-leaf-style is applied through el.style, and a style the hook changed since is kept", { skip: require("./support/dom.cjs").skip }, () => {
  require("./support/dom.cjs").editor("<p>x</p>"); // a DOM on globals
  const apply = new Function(lift("applyDataStyles") + "\nreturn applyDataStyles;")();
  const root = document.createElement("div");
  root.setAttribute("data-leaf-style", "container-type: inline-size;");
  root.innerHTML =
    '<div id="h" data-leaf-style="display:none"></div>' +
    '<div id="v" data-leaf-style="min-height: 200px; height: 200px;"></div>';
  document.body.appendChild(root);

  apply(root);
  assert.equal(root.style.containerType, "inline-size");
  assert.equal(root.querySelector("#h").style.display, "none");
  assert.equal(root.querySelector("#v").style.height, "200px");

  // The hook shows the handle; a later call (after a patch that did not
  // touch it) leaves it shown.
  root.querySelector("#h").style.display = "block";
  apply(root);
  assert.equal(root.querySelector("#h").style.display, "block");

  // A patch that reset it removes the attribute: the server's value is back.
  root.querySelector("#h").removeAttribute("style");
  apply(root);
  assert.equal(root.querySelector("#h").style.display, "none");
  root.remove();
});

test("#9: the hook applies data-leaf-style on mount and after every patch", () => {
  const mounted = SRC.slice(SRC.indexOf("  window.LeafHooks.Leaf = {"), SRC.indexOf("this._editorId = this.el.dataset.editorId"));
  assert.match(mounted, /applyDataStyles\(this\.el\);\s*this\.el\.dataset\.leafMountState = "ready";/);
  const updated = SRC.slice(SRC.indexOf("    updated() {"), SRC.indexOf("this._restoreToolbarState();", SRC.indexOf("    updated() {")));
  assert.match(updated, /applyDataStyles\(this\.el\);/);
});
