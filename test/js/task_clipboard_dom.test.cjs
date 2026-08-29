"use strict";

// A checklist row travels with its checkbox.
//
// The box is a contenteditable=false span with no text in it, so native copy
// gave just the label: paste the row anywhere and its state was gone. When
// the selection covers whole task rows and nothing else, the clipboard now
// carries GFM markdown as text and GFM html for the html path — the form our
// own paste (and GitHub's) rebuilds a working checkbox from.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function selectAll(node) {
  const range = document.createRange();
  range.selectNodeContents(node);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  return range;
}

function clipboardEvent(type) {
  const data = {};
  return {
    type,
    clipboardData: {
      setData: (kind, value) => {
        data[kind] = value;
      },
      getData: (kind) => data[kind],
    },
    prevented: false,
    preventDefault() {
      this.prevented = true;
    },
    data,
  };
}

function taskHtml(rows) {
  return (
    "<ul>" +
    rows
      .map(
        ([checked, label]) =>
          `<li class="leaf-task" data-checked="${checked}"><span class="leaf-task-box" contenteditable="false"></span>${label}</li>`
      )
      .join("") +
    "</ul>"
  );
}

test("copying a whole row carries its checkbox as markdown and html", { skip: dom.skip }, () => {
  const e = dom.editor(taskHtml([["true", "ship it"]]), "hybrid");
  selectAll(e._visualEl.querySelector("li"));

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.prevented, true, "the native text-only copy must not run");
  assert.equal(evt.data["text/plain"], "- [x] ship it");
  assert.match(evt.data["text/html"], /<input type="checkbox" checked> ship it/);

  e.cleanup();
});

test("several rows selected copy as a checklist", { skip: dom.skip }, () => {
  const e = dom.editor(
    taskHtml([
      ["false", "one"],
      ["true", "two"],
    ]),
    "hybrid"
  );
  selectAll(e._visualEl.querySelector("ul"));

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.data["text/plain"], "- [ ] one\n- [x] two");

  e.cleanup();
});

test("half a row stays with the native copy", { skip: dom.skip }, () => {
  const e = dom.editor(taskHtml([["false", "groceries"]]), "hybrid");
  const text = e._visualEl.querySelector("li").lastChild;
  const range = document.createRange();
  range.setStart(text, 0);
  range.setEnd(text, 4); // "groc"
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.prevented, false, "a partial row is not a row — native copy knows better");

  e.cleanup();
});

test("a row plus a paragraph stays with the native copy", { skip: dom.skip }, () => {
  const e = dom.editor(taskHtml([["false", "task"]]) + "<p>prose</p>", "hybrid");
  selectAll(e._visualEl);

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.prevented, false, "mixed selections are not whole rows");

  e.cleanup();
});

test("cut removes the rows it copied", { skip: dom.skip }, () => {
  const e = dom.editor(taskHtml([["false", "going"]]) + "<p>staying</p>", "hybrid");
  selectAll(e._visualEl.querySelector("ul"));

  const evt = clipboardEvent("cut");
  e._onCopyOrCut(evt);

  assert.equal(evt.data["text/plain"], "- [ ] going");
  assert.equal(e._visualEl.querySelector("ul"), null, "the emptied list goes with its last row");
  assert.ok(e._visualEl.querySelector("p"), "everything else stays");

  e.cleanup();
});

test("a row in source mode copies its label, not its marker text", { skip: dom.skip }, () => {
  // A row mid-edit carries "- [ ] " as literal span text; the clipboard must
  // not say "- [ ] - [ ] label".
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false" data-leaf-source="li">' +
      '<span class="leaf-task-box" contenteditable="false"></span>' +
      '<span class="leaf-source-marker leaf-list-marker">- [ ] </span>label</li></ul>',
    "hybrid"
  );
  selectAll(e._visualEl.querySelector("li"));

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.data["text/plain"], "- [ ] label");

  e.cleanup();
});

test("pasted GFM checkboxes become working task items", { skip: dom.skip }, () => {
  const e = dom.editor("<p>x</p>", "hybrid");
  const container = document.createElement("div");
  container.innerHTML =
    '<ul><li><input type="checkbox" checked> done thing</li><li><input type="checkbox"> open thing</li></ul>';

  e._adoptPastedCheckboxes(container);

  const items = container.querySelectorAll("li.leaf-task");
  assert.equal(items.length, 2);
  assert.equal(items[0].getAttribute("data-checked"), "true");
  assert.equal(items[1].getAttribute("data-checked"), "false");
  assert.ok(items[0].querySelector(".leaf-task-box"), "the box replaces the input");
  assert.equal(container.querySelector("input"), null, "no form controls in the content");
  assert.equal(items[0].textContent, "done thing", "the interchange space is gone");

  e.cleanup();
});

test("mounted actually wires copy and cut to the handler", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  assert.match(src, /addEventListener\("copy", this\._onCopyOrCut\.bind\(this\)\)/);
  assert.match(src, /addEventListener\("cut", this\._onCopyOrCut\.bind\(this\)\)/);
  assert.match(src, /_adoptPastedCheckboxes\(container\)/, "and paste runs the adopter");
});

// ---------------------------------------------------------------------------
// Selecting the row at all
// ---------------------------------------------------------------------------
//
// preventDefault on mousedown is how you make a row unselectable: a
// drag-selection that starts in the gutter died before it began, so the row
// could never be swept from its left edge — "it just selects the text no
// matter how much I try". The gestures now wait for mouseup and stand aside
// for anything that turned out to be a drag.

function fakeEvent(overrides) {
  return Object.assign(
    {
      clientX: 0,
      clientY: 0,
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
      stopPropagation() {},
      target: null,
    },
    overrides
  );
}

test("a mousedown in the gutter no longer kills the drag before it starts", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>hello row</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");

  const evt = fakeEvent({ target: li, clientX: 5, clientY: 10 });
  e._onTaskMouseDown(evt);

  assert.equal(evt.prevented, false, "the browser must be free to start a selection");
  assert.ok(e._taskGesture, "the maybe-click is remembered for mouseup to judge");

  e.cleanup();
});

test("a clean click in the gutter still opens the marker, on mouseup", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>hello row</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const box = li.querySelector(".leaf-task-box");
  box.getBoundingClientRect = () => ({ left: 30, width: 14, top: 0, height: 14 });

  let revealed = null;
  e._revealTaskMarker = (target) => {
    revealed = target;
    return true;
  };
  window.getSelection().removeAllRanges();

  e._onTaskMouseDown(fakeEvent({ target: li, clientX: 5, clientY: 10 }));
  e._onTaskMouseUp(fakeEvent({ target: li, clientX: 6, clientY: 11 }));

  assert.equal(revealed, li, "no drag happened, so the click means: edit the marker");

  e.cleanup();
});

test("a drag that ends with a selection is left entirely alone", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>hello row</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const box = li.querySelector(".leaf-task-box");
  box.getBoundingClientRect = () => ({ left: 30, width: 14, top: 0, height: 14 });

  let revealed = false;
  e._revealTaskMarker = () => {
    revealed = true;
    return true;
  };

  // The drag: down in the gutter, sweep across the row, selection exists.
  e._onTaskMouseDown(fakeEvent({ target: li, clientX: 5, clientY: 10 }));
  const text = li.lastChild;
  const range = document.createRange();
  range.setStart(text, 0);
  range.setEnd(text, text.length);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  e._onTaskMouseUp(fakeEvent({ target: li, clientX: 5, clientY: 10 }));

  assert.equal(revealed, false, "selecting must win over every gesture");
  assert.equal(sel.isCollapsed, false, "and the selection must still be standing");

  e.cleanup();
});

test("a fully selected row paints its checkbox as selected", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>hello row</li></ul>' +
      "<p>prose</p>",
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._mirrorTaskSelection();
  assert.equal(li.classList.contains("leaf-task-in-selection"), true);

  // Collapse the selection: the paint comes off.
  window.getSelection().removeAllRanges();
  e._mirrorTaskSelection();
  assert.equal(li.classList.contains("leaf-task-in-selection"), false);

  e.cleanup();
});

test("half a row does not paint the box", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>hello row</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const text = li.lastChild;
  const range = document.createRange();
  range.setStart(text, 0);
  range.setEnd(text, 5);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  e._mirrorTaskSelection();
  assert.equal(li.classList.contains("leaf-task-in-selection"), false);

  e.cleanup();
});

test("the listeners are wired in setup and removed in teardown", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  assert.match(src, /document\.addEventListener\("mouseup", this\._onTaskMouseUpBound\)/);
  assert.match(src, /document\.addEventListener\("selectionchange", this\._onTaskSelectionChange\)/);
  assert.match(src, /document\.removeEventListener\("mouseup", this\._onTaskMouseUpBound\)/);
  assert.match(
    src,
    /document\.removeEventListener\(\s*"selectionchange",\s*this\._onTaskSelectionChange\s*\)/
  );
});
