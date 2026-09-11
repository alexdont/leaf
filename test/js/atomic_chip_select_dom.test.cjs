"use strict";

// Click-selected atomic chips: the ring means the keyboard acts on the
// chip. Backspace deletes it (the one thing contenteditable=false made
// impossible outside the markdown tab), Enter opens a paragraph after
// its block, arrows step the caret out — creating the neighbor block
// when the chip ends the document.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

const CHIP =
  '<p><span class="leaf-atomic leaf-atomic-block" contenteditable="false"' +
  ' data-leaf-raw="&lt;Embed src=&quot;/x&quot; /&gt;" data-leaf-tag="Embed">' +
  '<span class="leaf-atomic-name">Embed</span></span></p>';

function chipEditor(extra) {
  const e = editor(CHIP + (extra || ""), "hybrid");
  return e;
}

function key(name, opts) {
  const ev = new window.KeyboardEvent("keydown", Object.assign({ key: name, bubbles: true, cancelable: true }, opts || {}));
  return ev;
}

test("clicking a chip selects it, clicking elsewhere deselects", { skip }, () => {
  const e = chipEditor("<p>after</p>");
  const chip = e._visualEl.querySelector(".leaf-atomic");

  e._selectAtomicChip(chip);
  assert.ok(chip.classList.contains("leaf-atomic-selected"));
  assert.equal(e._selectedAtomic, chip);

  e._selectAtomicChip(null);
  assert.ok(!chip.classList.contains("leaf-atomic-selected"));
  assert.equal(e._selectedAtomic, null);
  e.cleanup();
});

test("Backspace deletes the selected chip and leaves a caretable block", { skip }, () => {
  const e = chipEditor("<p>after</p>");
  const chip = e._visualEl.querySelector(".leaf-atomic");
  e._selectAtomicChip(chip);

  const ev = key("Backspace");
  assert.ok(e._atomicSelectionKeydown(ev), "handled");
  assert.ok(ev.defaultPrevented);
  assert.equal(e._visualEl.querySelector(".leaf-atomic"), null, "chip gone");
  assert.equal(
    e._visualEl.firstElementChild.innerHTML.toLowerCase(),
    "<br>",
    "the lone-chip host becomes an empty paragraph"
  );
  e.cleanup();
});

test("Enter opens a paragraph after the chip's block", { skip }, () => {
  const e = chipEditor();
  const chip = e._visualEl.querySelector(".leaf-atomic");
  e._selectAtomicChip(chip);

  assert.ok(e._atomicSelectionKeydown(key("Enter")));
  const blocks = e._visualEl.children;
  assert.equal(blocks.length, 2);
  assert.ok(blocks[0].querySelector(".leaf-atomic"), "chip block intact");
  assert.equal(blocks[1].tagName.toLowerCase(), "p", "fresh paragraph after");
  e.cleanup();
});

test("ArrowRight past a document-ending chip creates the next paragraph", { skip }, () => {
  const e = chipEditor();
  const chip = e._visualEl.querySelector(".leaf-atomic");
  e._selectAtomicChip(chip);

  assert.ok(e._atomicSelectionKeydown(key("ArrowRight")));
  assert.equal(e._visualEl.children.length, 2, "paragraph created to step into");
  assert.equal(e._selectedAtomic, null, "selection dropped");
  e.cleanup();
});

test("modifier chords pass through unhandled", { skip }, () => {
  const e = chipEditor();
  const chip = e._visualEl.querySelector(".leaf-atomic");
  e._selectAtomicChip(chip);

  assert.equal(e._atomicSelectionKeydown(key("c", { ctrlKey: true })), false);
  assert.ok(e._visualEl.querySelector(".leaf-atomic"), "chip untouched");
  e.cleanup();
});
