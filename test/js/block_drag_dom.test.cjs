"use strict";

// Reordering blocks with the drag handle. jsdom has no layout, so each block
// is given a stacked box (20px tall, 20px apart from the top) and the
// wrapper sits at the origin.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function dragEditor(html) {
  const e = dom.editor(html, "visual");
  // The drag setup watches for new images; the shared helper does not expose
  // jsdom's observer as a global.
  global.MutationObserver = window.MutationObserver;
  const wrapper = document.createElement("div");
  const handle = document.createElement("div");
  handle.setAttribute("data-drag-handle", "");
  e._visualEl.parentNode.insertBefore(wrapper, e._visualEl);
  wrapper.appendChild(handle);
  wrapper.appendChild(e._visualEl);
  e._visualWrapper = wrapper;
  e.el = wrapper;

  const blocks = Array.from(e._visualEl.children);
  blocks.forEach((b, i) => {
    b.getBoundingClientRect = () => ({ top: i * 20, bottom: i * 20 + 20, left: 0, right: 100, height: 20, width: 100 });
  });
  wrapper.getBoundingClientRect = () => ({ top: 0, bottom: blocks.length * 20, left: 0, right: 100, height: blocks.length * 20, width: 100 });

  e.pushes = 0;
  e._debouncedPushVisualChange = () => e.pushes++;
  e._dismissImagePopover = () => {};
  e._openBlockMenu = (b) => (e.menuFor = b);
  Object.getPrototypeOf(e)._setupImageDragAndDrop.call(e);

  const cleanup = e.cleanup;
  e.cleanup = () => {
    cleanup();
    wrapper.remove();
    if (e._imgObserver) e._imgObserver.disconnect();
  };
  e.handle = handle;
  return e;
}

// Grab `block` by its handle, move the pointer to each y in turn, release.
function drag(e, block, ...ys) {
  e._dragHandleBlock = block;
  const start = block.getBoundingClientRect().top + 5;
  e.handle.dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true, cancelable: true, clientX: 5, clientY: start }));
  for (const y of ys) {
    document.dispatchEvent(new window.MouseEvent("mousemove", { bubbles: true, cancelable: true, clientX: 5, clientY: y }));
  }
  document.dispatchEvent(new window.MouseEvent("mouseup", { bubbles: true, clientX: 5, clientY: ys[ys.length - 1] ?? start }));
}

const order = (e) => Array.from(e._visualEl.children).map((b) => b.textContent);
const THREE = "<p>A</p><p>B</p><p>C</p>";

test("dragging a block below the last one moves it to the end", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  drag(e, e._visualEl.children[0], 55);
  assert.deepEqual(order(e), ["B", "C", "A"]);
  assert.equal(e._currentMarkdown().trim(), "B\n\nC\n\nA");
  assert.equal(e.pushes, 1);
  e.cleanup();
});

test("dragging a block above the first one moves it to the start", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  drag(e, e._visualEl.children[2], -10);
  assert.deepEqual(order(e), ["C", "A", "B"]);
  e.cleanup();
});

test("dropping next to where it already is changes nothing", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  // The slot just above B's next sibling (C) is where B already sits.
  drag(e, e._visualEl.children[1], 41);
  assert.deepEqual(order(e), ["A", "B", "C"]);
  e.cleanup();
});

test("a click on the handle without moving opens the block menu instead", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  const a = e._visualEl.children[0];
  drag(e, a);
  assert.equal(e.menuFor, a);
  assert.deepEqual(order(e), ["A", "B", "C"]);
  assert.equal(e.pushes, 0);
  e.cleanup();
});

test("the drag marks the block while it moves and cleans up after", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  const a = e._visualEl.children[0];
  e._dragHandleBlock = a;
  e.handle.dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true, cancelable: true, clientY: 5 }));
  assert.ok(a.classList.contains("leaf-dragging"));
  assert.ok(e._visualWrapper.querySelector(".leaf-drop-indicator"));
  document.dispatchEvent(new window.MouseEvent("mousemove", { bubbles: true, cancelable: true, clientY: 55 }));
  document.dispatchEvent(new window.MouseEvent("mouseup", { bubbles: true }));
  assert.ok(!a.classList.contains("leaf-dragging"));
  assert.equal(e._visualWrapper.querySelector(".leaf-drop-indicator"), null);
  assert.equal(e._dragSourceBlock, null);
  e.cleanup();
});

test("readonly: the handle does nothing", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  e._readonly = true;
  drag(e, e._visualEl.children[0], 55);
  assert.deepEqual(order(e), ["A", "B", "C"]);
  assert.equal(e.menuFor, undefined);
  e.cleanup();
});

test("lists, tables and headings move as whole blocks", { skip: dom.skip }, () => {
  const e = dragEditor("<h2>T</h2><ul><li>one</li><li>two</li></ul><table><tr><th>h</th></tr><tr><td>c</td></tr></table>");
  drag(e, e._visualEl.children[1], 65);
  assert.deepEqual(Array.from(e._visualEl.children).map((b) => b.tagName), ["H2", "TABLE", "UL"]);
  assert.equal(e._currentMarkdown().trim(), "## T\n\n| h |\n| --- |\n| c |\n\n- one\n- two");
  e.cleanup();
});

test("a moved block can be undone and redone", { skip: dom.skip }, () => {
  const e = dragEditor(THREE);
  delete e._historyCapture;
  delete e._historyCaptureNow;
  e._historyInit();

  drag(e, e._visualEl.children[0], 55);
  assert.deepEqual(order(e), ["B", "C", "A"]);

  e._historyUndo();
  assert.deepEqual(order(e), ["A", "B", "C"]);
  e._historyRedo();
  assert.deepEqual(order(e), ["B", "C", "A"]);
  e.cleanup();
});

test(
  "a collapsible <details> block gets the drag handle like other blocks",
  { skip: dom.skip },
  () => {
    const e = dragEditor("<p>A</p><details open><summary>S</summary><p>body</p></details><p>C</p>");
    const details = e._visualEl.querySelector("details");
    assert.equal(e._getHoveredBlock(details.querySelector("summary")), details);
    e.cleanup();
  }
);
