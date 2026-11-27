"use strict";

// Browser side of GitHub issues #4–#8.
//
//   #8, #5  A LiveView patch must not undo the hook's toolbar state: the
//           overflow attributes, the sticky class and its placeholder.
//   #4      Enter brings the caret into view inside a scrolling editor.
//   #7      A mention chip carries its token's type and id.
//   #6      A suggestion row can show an avatar (picture or initials).
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert/strict");
const dom = require("./support/dom.cjs");

const skip = dom.skip;
const UUID = "0190aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee";

test("#8/#5: a patch keeps the toolbar's overflow state, sticky state and placeholder", { skip }, () => {
  const e = dom.editor("<p>x</p>");
  const toolbar = document.createElement("div");
  toolbar.setAttribute("data-visual-toolbar", "");
  e.el.appendChild(toolbar);
  const placeholder = document.createElement("div");
  placeholder.className = "leaf-toolbar-placeholder";
  e.el.insertBefore(placeholder, toolbar);
  e._stickyToolbarEl = toolbar;
  e._stickyPlaceholder = placeholder;

  toolbar.dataset.compactModes = "true";
  toolbar.dataset.toolbarOverflowLevel = "3";
  toolbar.classList.add("leaf-toolbar-sticky");
  toolbar.style.width = "500px";
  toolbar.style.top = "64px";

  e.beforeUpdate();
  // What LiveView's patch does to the server-rendered markup:
  delete toolbar.dataset.compactModes;
  delete toolbar.dataset.toolbarOverflowLevel;
  toolbar.classList.remove("leaf-toolbar-sticky");
  toolbar.style.width = "";
  toolbar.style.top = "";
  placeholder.remove();
  e._restoreToolbarState();

  assert.equal(toolbar.dataset.compactModes, "true");
  assert.equal(toolbar.dataset.toolbarOverflowLevel, "3");
  assert.ok(toolbar.classList.contains("leaf-toolbar-sticky"));
  assert.equal(toolbar.style.width, "500px");
  assert.equal(toolbar.style.top, "64px");
  assert.equal(toolbar.previousSibling, placeholder, "placeholder back in front of the toolbar");
  e.cleanup();
});

test("#8: a patch with nothing to restore leaves the toolbar alone", { skip }, () => {
  const e = dom.editor("<p>x</p>");
  const toolbar = document.createElement("div");
  toolbar.setAttribute("data-visual-toolbar", "");
  e.el.appendChild(toolbar);
  e.beforeUpdate();
  e._restoreToolbarState();
  assert.equal(toolbar.dataset.compactModes, undefined);
  assert.equal(toolbar.classList.contains("leaf-toolbar-sticky"), false);
  e.cleanup();
});

test("#4: the caret below the editor's visible area is scrolled into view", { skip }, () => {
  const e = dom.editor("<p>one</p><p>two</p>");
  const box = e._visualEl;
  Object.defineProperty(box, "scrollHeight", { value: 500, configurable: true });
  Object.defineProperty(box, "clientHeight", { value: 200, configurable: true });
  box.scrollTop = 0;
  box.getBoundingClientRect = () => ({ top: 100, bottom: 300, left: 0, right: 400, height: 200, width: 400 });
  const p = box.lastChild;
  const r = document.createRange();
  r.selectNodeContents(p);
  r.collapse(false);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(r);
  // the caret sits 40px below the editor's bottom edge until the box scrolls
  const realRange = window.Range.prototype.getBoundingClientRect;
  window.Range.prototype.getBoundingClientRect = function () {
    const y = 340 - box.scrollTop;
    return { top: y - 18, bottom: y, left: 0, right: 0, height: 18, width: 0 };
  };
  window.scrollBy = () => {};
  try {
    e._getStickyTopOffset = () => 0;
    e._scrollCaretIntoView();
  } finally {
    window.Range.prototype.getBoundingClientRect = realRange;
  }
  assert.equal(box.scrollTop, 48, "scrolled by the overshoot plus 8px of air");
  e.cleanup();
});

test("#7: a chip carries the token's type and id", { skip }, () => {
  const e = dom.editor("<p>x</p>");
  const chip = e._mentionChip(`@[user:${UUID}|Ada]`, "@", "Ada");
  assert.equal(chip.getAttribute("data-leaf-mention-type"), "user");
  assert.equal(chip.getAttribute("data-leaf-mention-id"), UUID);
  assert.equal(chip.textContent, "@Ada");

  const rec = e._mentionChip(`#[project:${UUID}|Q3]`, "#", "Q3");
  assert.equal(rec.getAttribute("data-leaf-mention-type"), "project");
  e.cleanup();
});

test("#6: an avatar row shows the picture, initials meanwhile and as the fallback", { skip }, () => {
  const e = dom.editor("<p>x</p>");

  const pic = e._suggestAvatar({ url: "/u/a.jpg", initials: "AK" });
  const img = pic.querySelector("img");
  assert.ok(img, "picture shown");
  assert.equal(img.getAttribute("src"), "/u/a.jpg");
  assert.equal(img.getAttribute("alt"), "");
  img.dispatchEvent(new window.Event("error"));
  assert.equal(pic.querySelector("img"), null, "a broken picture gives way");
  assert.equal(pic.textContent, "AK", "to the initials");

  const initials = e._suggestAvatar({ initials: "BO" });
  assert.equal(initials.querySelector("img"), null);
  assert.equal(initials.textContent, "BO");

  const bad = e._suggestAvatar({ url: "javascript:alert(1)", initials: "X" });
  assert.equal(bad.querySelector("img"), null, "an unsafe URL is never used");
  assert.equal(bad.textContent, "X");

  const html = e._suggestAvatar({ initials: "<b>x</b>" });
  assert.equal(html.querySelector("b"), null, "initials are text, never markup");
  e.cleanup();
});
