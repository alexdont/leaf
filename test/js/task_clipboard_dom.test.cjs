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
  assert.match(evt.data["text/html"], /<input type="checkbox" checked(="")?> ship it/);

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
  assert.equal(li.classList.contains("leaf-row-in-selection"), true);

  // Collapse the selection: the paint comes off.
  window.getSelection().removeAllRanges();
  e._mirrorTaskSelection();
  assert.equal(li.classList.contains("leaf-row-in-selection"), false);

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
  assert.equal(li.classList.contains("leaf-row-in-selection"), false);

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

// ---------------------------------------------------------------------------
// The selection shows the source, like Obsidian
// ---------------------------------------------------------------------------

test("a covered source-mode row reveals its real marker text", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false" data-leaf-source="li">' +
      '<span class="leaf-task-box" contenteditable="false"></span>' +
      '<span class="leaf-source-marker leaf-list-marker">- [ ] </span>hello row</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._mirrorTaskSelection();
  assert.equal(
    li.classList.contains("leaf-marker-active"),
    true,
    "the hidden `- [ ] ` span becomes visible — real text, natively highlighted"
  );

  window.getSelection().removeAllRanges();
  e._mirrorTaskSelection();
  assert.equal(
    li.classList.contains("leaf-marker-active"),
    false,
    "and is handed back when the selection goes"
  );

  e.cleanup();
});

test("the css reveals the row's marker under the selection", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  assert.match(
    src,
    /leaf-row-in-selection:not\(\[data-leaf-source\]\)::before/,
    "pseudo marker on covered rows"
  );
  assert.match(src, /content: attr\(data-leaf-selmarker\)/, "whatever marker the mirror computed");
  assert.match(
    src,
    /leaf-row-in-selection:not\(\[data-leaf-source\]\) > \.leaf-task-box \{",\s*\n\s*"\s*display: none;/,
    "the box steps aside while the marker shows"
  );
});

// ---------------------------------------------------------------------------
// Plain bullets and numbered rows get the same treatment
// ---------------------------------------------------------------------------

test("a fully selected bullet row reveals '- '", { skip: dom.skip }, () => {
  const e = dom.editor("<ul><li>hello row</li></ul>", "hybrid");
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._mirrorTaskSelection();

  assert.equal(li.classList.contains("leaf-row-in-selection"), true);
  assert.equal(li.getAttribute("data-leaf-selmarker"), "- ");

  e.cleanup();
});

test("a numbered row reveals its own number, start included", { skip: dom.skip }, () => {
  const e = dom.editor('<ol start="7"><li>seven</li><li>eight</li></ol>', "hybrid");
  const second = e._visualEl.querySelectorAll("li")[1];
  selectAll(second);

  e._mirrorTaskSelection();

  assert.equal(second.getAttribute("data-leaf-selmarker"), "8. ",
    "the number the row actually wears, not a generic 1.");

  e.cleanup();
});

test("a checked task in a numbered list reveals 'N. [x] '", { skip: dom.skip }, () => {
  // The case the css-only approach could not do at all: the number is not
  // knowable to a static content rule.
  const e = dom.editor(
    '<ol start="3"><li class="leaf-task" data-checked="true"><span class="leaf-task-box" contenteditable="false"></span>done</li></ol>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._mirrorTaskSelection();

  assert.equal(li.getAttribute("data-leaf-selmarker"), "3. [x] ");

  e.cleanup();
});

test("copying bullet rows carries their markers", { skip: dom.skip }, () => {
  const e = dom.editor("<ul><li>one</li><li>two</li></ul>", "hybrid");
  selectAll(e._visualEl.querySelector("ul"));

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.data["text/plain"], "- one\n- two");
  assert.match(evt.data["text/html"], /<ul><li>one<\/li><li>two<\/li><\/ul>/);

  e.cleanup();
});

test("copying numbered rows keeps their numbering", { skip: dom.skip }, () => {
  const e = dom.editor('<ol start="3"><li>x</li><li>y</li></ol>', "hybrid");
  selectAll(e._visualEl.querySelector("ol"));

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(evt.data["text/plain"], "3. x\n4. y",
    "the numbers the rows wear, so pasting elsewhere reads the same");
  assert.match(evt.data["text/html"], /<ol start="3">/);

  e.cleanup();
});

test("a nested list copies indented under its parent", { skip: dom.skip }, () => {
  const e = dom.editor(
    "<ul><li>parent<ul><li>child</li></ul></li></ul>",
    "hybrid"
  );
  selectAll(e._visualEl.querySelector("ul"));

  const evt = clipboardEvent("copy");
  e._onCopyOrCut(evt);

  assert.equal(
    evt.data["text/plain"],
    "- parent\n  - child",
    "the serializer's own two-space indent, so it pastes back as it copied out"
  );

  e.cleanup();
});

test("cut on bullet rows removes them and their emptied list", { skip: dom.skip }, () => {
  const e = dom.editor("<ul><li>going</li></ul><p>staying</p>", "hybrid");
  selectAll(e._visualEl.querySelector("ul"));

  const evt = clipboardEvent("cut");
  e._onCopyOrCut(evt);

  assert.equal(evt.data["text/plain"], "- going");
  assert.equal(e._visualEl.querySelector("ul"), null);
  assert.ok(e._visualEl.querySelector("p"));

  e.cleanup();
});

// ---------------------------------------------------------------------------
// The mirror must never mutate mid-keystroke
// ---------------------------------------------------------------------------
//
// Typing over a selection is one editing command: the browser deletes the
// selection, a selectionchange fires in the middle, and then the key is
// inserted. A DOM mutation from inside that event makes engines abandon the
// insertion — so marked rows being unmarked synchronously killed the
// keystroke: select a word in a short row, type, nothing.

test("the selectionchange listener defers; nothing mutates synchronously", { skip: dom.skip }, async () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>word</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._scheduleTaskSelectionMirror();
  assert.equal(
    li.classList.contains("leaf-row-in-selection"),
    false,
    "inside the event, the DOM must be left exactly alone"
  );

  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(
    li.classList.contains("leaf-row-in-selection"),
    true,
    "the reveal lands a frame later, after the editing command is done"
  );

  e.cleanup();
});

test("a burst of selection changes coalesces into one deferred run", { skip: dom.skip }, async () => {
  const e = dom.editor("<ul><li>word</li></ul>", "hybrid");
  let runs = 0;
  const real = e._mirrorTaskSelection.bind(e);
  e._mirrorTaskSelection = () => {
    runs++;
    real();
  };

  e._scheduleTaskSelectionMirror();
  e._scheduleTaskSelectionMirror();
  e._scheduleTaskSelectionMirror();

  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(runs, 1, "a drag fires selectionchange constantly; one run answers them all");

  e.cleanup();
});

test("an unchanged covered set writes nothing to the DOM", { skip: dom.skip }, async () => {
  const e = dom.editor("<ul><li>word</li></ul>", "hybrid");
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._mirrorTaskSelection();
  assert.equal(li.classList.contains("leaf-row-in-selection"), true);

  const observer = new window.MutationObserver(() => {});
  observer.observe(li, { attributes: true });

  // The selection has not moved; the mirror runs again (as it does on every
  // selectionchange during a drag) and must have nothing to say.
  e._mirrorTaskSelection();

  assert.deepEqual(observer.takeRecords(), [], "rewriting the same state is churn");
  observer.disconnect();

  e.cleanup();
});

test("the listener is the scheduler, not the mirror itself", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  assert.match(
    src,
    /this\._onTaskSelectionChange = this\._scheduleTaskSelectionMirror\.bind\(this\)/,
    "wiring the mirror in directly is the bug back again"
  );
});

test("the source machinery is deferred off selectionchange too", { skip: dom.skip }, () => {
  // The same editing-command collision, one listener over: this one is the
  // source machinery's only driver, and entering/refreshing source mode
  // rebuilds the block's children — done synchronously mid-command, the
  // keystroke's insertion finds its target gone and dies.
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  const listener = src.slice(
    src.indexOf("// DEFERRED, never synchronous, for the same reason the selection"),
    src.indexOf("_updateSyntaxDecorations:")
  );

  assert.match(listener, /_sourceUpdateScheduled/, "coalesced like the mirror");
  assert.ok(
    /requestAnimationFrame\(run\)/.test(listener),
    "and pushed past the editing command before _updateSourceBlock may run"
  );
  assert.ok(
    listener.indexOf("requestAnimationFrame") <
      listener.indexOf("self._updateSourceBlock()") ||
      /var run = function/.test(listener),
    "the update lives inside the deferred body"
  );
});
