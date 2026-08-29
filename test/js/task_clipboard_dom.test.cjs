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
