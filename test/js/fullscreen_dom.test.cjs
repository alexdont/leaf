"use strict";

// The fullscreen toggle: it asks the browser, and the editor reflects
// whatever the browser decided (fullscreenchange), not what it asked for.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function fsEditor() {
  const e = dom.editor("<p>x</p>", "visual");
  const root = document.createElement("div");
  root.innerHTML =
    '<button data-leaf-fullscreen-btn><span data-leaf-fullscreen-enter></span>' +
    '<span data-leaf-fullscreen-exit style="display:none"></span></button>';
  e._visualEl.parentNode.insertBefore(root, e._visualEl);
  root.appendChild(e._visualEl);
  e.el = root;
  const cleanup = e.cleanup;
  e.cleanup = () => {
    cleanup();
    root.remove();
    setFullscreenElement(null);
  };
  return e;
}

function setFullscreenElement(el) {
  Object.defineProperty(document, "fullscreenElement", { value: el, configurable: true });
}

test("the toggle requests fullscreen on the editor root", { skip: dom.skip }, () => {
  const e = fsEditor();
  let requested = null;
  e.el.requestFullscreen = function () { requested = this; };
  setFullscreenElement(null);
  e._toggleFullscreen();
  assert.equal(requested, e.el);
  e.cleanup();
});

test("the toggle exits when the editor is already fullscreen", { skip: dom.skip }, () => {
  const e = fsEditor();
  let exited = false;
  document.exitFullscreen = () => { exited = true; };
  setFullscreenElement(e.el);
  e._toggleFullscreen();
  assert.ok(exited);
  delete document.exitFullscreen;
  e.cleanup();
});

test("another element being fullscreen means request, not exit", { skip: dom.skip }, () => {
  const e = fsEditor();
  let requested = false;
  e.el.requestFullscreen = () => { requested = true; };
  setFullscreenElement(document.body);
  e._toggleFullscreen();
  assert.ok(requested);
  e.cleanup();
});

test("the webkit-prefixed API is used when the standard one is missing", { skip: dom.skip }, () => {
  const e = fsEditor();
  let requested = false;
  e.el.requestFullscreen = undefined;
  e.el.webkitRequestFullscreen = () => { requested = true; };
  setFullscreenElement(null);
  e._toggleFullscreen();
  assert.ok(requested);
  e.cleanup();
});

test("a refused request is swallowed", { skip: dom.skip }, () => {
  const e = fsEditor();
  e.el.requestFullscreen = () => { throw new Error("not allowed"); };
  setFullscreenElement(null);
  assert.doesNotThrow(() => e._toggleFullscreen());
  e.cleanup();
});

test("state follows the browser: attribute, button title and icon", { skip: dom.skip }, () => {
  const e = fsEditor();
  const btn = e.el.querySelector("[data-leaf-fullscreen-btn]");
  const enter = e.el.querySelector("[data-leaf-fullscreen-enter]");
  const exit = e.el.querySelector("[data-leaf-fullscreen-exit]");

  setFullscreenElement(e.el);
  e._syncFullscreenState();
  assert.equal(e.el.getAttribute("data-leaf-fullscreen"), "true");
  assert.equal(btn.title, "Exit fullscreen");
  assert.equal(enter.style.display, "none");
  assert.equal(exit.style.display, "");

  setFullscreenElement(null);
  e._syncFullscreenState();
  assert.equal(e.el.hasAttribute("data-leaf-fullscreen"), false);
  assert.equal(btn.title, "Toggle fullscreen");
  assert.equal(enter.style.display, "");
  assert.equal(exit.style.display, "none");
  e.cleanup();
});

test("fullscreen works in readonly and in markdown mode", { skip: dom.skip }, () => {
  for (const mode of ["visual", "markdown"]) {
    const e = fsEditor();
    e._mode = mode;
    e._readonly = true;
    let requested = false;
    e.el.requestFullscreen = () => { requested = true; };
    setFullscreenElement(null);
    e._execToolbarAction("fullscreen");
    assert.ok(requested, mode);
    e.cleanup();
  }
});
