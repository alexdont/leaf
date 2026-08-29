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

test("mid-command, the mirror waits; idle, it runs at once", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>word</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  // An editing command is in flight: the browser is between beforeinput and
  // input, and a DOM mutation here is what killed the keystroke.
  e._typingCommandOpen = true;
  e._scheduleTaskSelectionMirror();
  assert.equal(
    li.classList.contains("leaf-row-in-selection"),
    false,
    "mid-command, the DOM must be left exactly alone"
  );

  // The command completes; its input event flushes the queue.
  e._flushAfterCommand();
  assert.equal(
    li.classList.contains("leaf-row-in-selection"),
    true,
    "and the deferred work lands immediately after, before any next keystroke"
  );

  e.cleanup();
});

test("idle scheduling is synchronous — deferring always re-broke typing order", { skip: dom.skip }, () => {
  // The first cure deferred everything to the next frame; the marker
  // auto-format rebuild then landed BETWEEN keystrokes and re-seated the
  // caret, so fast typing interleaved out of order. Idle work must not wait.
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>word</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  selectAll(li);

  e._scheduleTaskSelectionMirror();
  assert.equal(
    li.classList.contains("leaf-row-in-selection"),
    true,
    "no command in flight, no reason to wait"
  );

  e.cleanup();
});

test("a burst mid-command coalesces into one run at the flush", { skip: dom.skip }, () => {
  const e = dom.editor("<ul><li>word</li></ul>", "hybrid");
  let runs = 0;
  const real = e._mirrorTaskSelection.bind(e);
  e._mirrorTaskSelection = () => {
    runs++;
    real();
  };

  e._typingCommandOpen = true;
  e._scheduleTaskSelectionMirror();
  e._scheduleTaskSelectionMirror();
  e._scheduleTaskSelectionMirror();
  assert.equal(runs, 0, "nothing until the command completes");

  e._flushAfterCommand();
  assert.equal(runs, 1, "one run answers the whole burst");

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

test("input is what flushes the command gate", { skip: dom.skip }, () => {
  // The queue drains on the command's own input event — calling the flush by
  // hand in tests proves nothing about the wiring that makes it real.
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");
  const setup = src.slice(
    src.indexOf("_setupCommandWindow: function"),
    src.indexOf("_setupTypingDiagnostics: function")
  );

  assert.match(setup, /addEventListener\("beforeinput"/, "beforeinput opens the window");
  assert.match(
    setup,
    /addEventListener\("input", function \(\) \{\s*self\._flushAfterCommand\(\);/,
    "and input closes it, flushing what waited"
  );
});

test("the source machinery goes through the command gate too", { skip: dom.skip }, () => {
  // Same editing-command collision, one listener over: entering/refreshing
  // source mode rebuilds the block's children, and doing that synchronously
  // mid-command killed the keystroke's insertion.
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  const listener = src.slice(
    src.indexOf("// DEFERRED, never synchronous, for the same reason the selection"),
    src.indexOf("_updateSyntaxDecorations:")
  );

  assert.match(listener, /_sourceUpdateScheduled/, "coalesced");
  assert.match(
    listener,
    /_afterEditingCommand\(run\)/,
    "dispatched through the gate: sync when idle, after the command when not"
  );
});

test("typing diagnostics exist, stay silent unarmed, and are torn down", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  assert.match(src, /LEAF_DEBUG_TYPING/, "armed from the console, not shipped on");
  assert.match(src, /NO INPUT FOLLOWED/, "the abort signal is the whole point");
  assert.match(src, /_typingDiagObserver\.disconnect\(\)/, "observers do not outlive the editor");
});

// ---------------------------------------------------------------------------
// Multi-clicks are selections, not gestures
// ---------------------------------------------------------------------------
//
// In some browsers the word-selection is not committed yet at the second
// mouseup, so "is anything selected?" answers no at exactly the wrong moment
// — and the stranded-caret corrector collapsed the fresh selection to after
// the box. The highlight still painted; typing went to a caret nobody could
// see. Only the first word, the one inside the box's stranding zone, and
// only by mouse: shift+arrow selections never touch this handler.

test("the second mouseup of a double-click runs no gesture at all", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const box = li.querySelector(".leaf-task-box");
  box.getBoundingClientRect = () => ({ left: 30, width: 14, top: 0, height: 14 });

  // The browser that bites: selection still COLLAPSED at mouseup #2.
  const text = li.lastChild;
  const r = document.createRange();
  r.setStart(text, 1);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  // caretFromPoint resolving into the stranding zone, as it does for the
  // first word.
  e._caretFromPoint = () => ({ node: li, offset: 0 });

  e._onTaskMouseDown(fakeEvent({ target: li, clientX: 50, clientY: 7, detail: 2 }));
  e._onTaskMouseUp(fakeEvent({ target: li, clientX: 50, clientY: 7, detail: 2 }));

  const after = window.getSelection().getRangeAt(0);
  assert.equal(after.startContainer, text, "the caret must be exactly where the click left it");
  assert.equal(after.startOffset, 1, "not corrected away from a selection mid-construction");

  e.cleanup();
});

test("a single click in the stranding zone still gets corrected", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const box = li.querySelector(".leaf-task-box");
  box.getBoundingClientRect = () => ({ left: 30, width: 14, top: 0, height: 14 });

  const r = document.createRange();
  r.setStart(li, 0);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  e._caretFromPoint = () => ({ node: li, offset: 0 });

  e._onTaskMouseDown(fakeEvent({ target: li, clientX: 50, clientY: 7, detail: 1 }));
  e._onTaskMouseUp(fakeEvent({ target: li, clientX: 50, clientY: 7, detail: 1 }));

  const after = window.getSelection().getRangeAt(0);
  assert.notEqual(
    after.startContainer === li && after.startOffset === 0,
    true,
    "the single-click correction is the behaviour worth keeping"
  );

  e.cleanup();
});

// ---------------------------------------------------------------------------
// Selections that swallowed the box get shrunk before the engine edits
// ---------------------------------------------------------------------------
//
// An edit whose range contains a contenteditable=false island is silently
// dropped by some engines. Double-click on the first word can anchor the
// range at the row boundary — before the box — and a whole-row sweep
// contains it outright; both look like ordinary text selections, and typing
// over them did nothing. Plain rows have no box, which is why "lists work,
// checkboxes don't".

test("a range starting before the box is shrunk to its text", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const text = li.lastChild;

  // The dblclick-on-first-word shape: start at (li, 0) — BEFORE the box —
  // end after "does". Selects the same characters as a text-anchored range.
  const r = document.createRange();
  r.setStart(li, 0);
  r.setEnd(text, 4);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  e._shrinkSelectionPastTaskBoxes();

  const after = window.getSelection().getRangeAt(0);
  assert.equal(after.startContainer, text, "anchored in the text, past the box");
  assert.equal(after.startOffset, 0);
  assert.equal(String(window.getSelection()), "does", "the selected characters are unchanged");

  e.cleanup();
});

test("a whole-row sweep keeps its text but releases the box", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");

  const r = document.createRange();
  r.selectNodeContents(li);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  e._shrinkSelectionPastTaskBoxes();

  const after = window.getSelection().getRangeAt(0);
  const boxRange = document.createRange();
  boxRange.selectNode(li.querySelector(".leaf-task-box"));
  assert.equal(
    after.compareBoundaryPoints(Range.START_TO_START, boxRange) > 0,
    true,
    "the box is out of the range — an engine will now accept the edit"
  );
  assert.equal(String(window.getSelection()), "does yes", "every character still selected");

  e.cleanup();
});

test("a text-only selection is left untouched", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const text = e._visualEl.querySelector("li").lastChild;
  const r = document.createRange();
  r.setStart(text, 0);
  r.setEnd(text, 4);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  e._shrinkSelectionPastTaskBoxes();

  const after = window.getSelection().getRangeAt(0);
  assert.equal(after.startContainer, text);
  assert.equal(after.startOffset, 0, "already editable — nothing to fix, nothing touched");

  e.cleanup();
});

test("the edit is intercepted at beforeinput, and selections are never touched at rest", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");

  // The keydown shrink is the bug two ways: it rewrote the selection in the
  // keystroke's face — "NO INPUT FOLLOWED", the engine abandoning the edit —
  // and it ran on shift+arrow, snapping the anchor away mid-extension.
  const keydownHead = src.slice(
    src.indexOf("_onVisualKeydown: function"),
    src.indexOf("_suggestKeydown(e)")
  );
  assert.doesNotMatch(keydownHead, /_shrinkSelectionPastTaskBoxes/);

  const gate = src.slice(
    src.indexOf("_setupCommandWindow: function"),
    src.indexOf("_setupTypingDiagnostics: function")
  );
  assert.match(gate, /_selectionHoldsTaskBox\(\)/, "detected where edits begin");
  assert.match(gate, /e\.preventDefault\(\)/, "the native command is cancelled outright");
  // BY HAND, not execCommand: running execCommand from inside the cancelled
  // command's dispatch nested one editing command in another, and characters
  // landed in neighbouring rows.
  assert.match(gate, /editRange\.deleteContents\(\)/);
  assert.match(gate, /createTextNode\(e\.data/);
  assert.doesNotMatch(gate, /execCommand\("insertText"/);
});

test("_selectionHoldsTaskBox tells the refusing shape from a plain one", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const text = li.lastChild;
  const sel = window.getSelection();

  const r1 = document.createRange();
  r1.setStart(li, 0);
  r1.setEnd(text, 4);
  sel.removeAllRanges();
  sel.addRange(r1);
  assert.equal(e._selectionHoldsTaskBox(), true, "the double-click shape");

  const r2 = document.createRange();
  r2.setStart(text, 0);
  r2.setEnd(text, 4);
  sel.removeAllRanges();
  sel.addRange(r2);
  assert.equal(e._selectionHoldsTaskBox(), false, "the drag shape — nothing to fix");

  e.cleanup();
});

// The comparator bug that sent typed characters into the NEXT row: a box
// entirely after the selection read as contained, the shrink moved the range
// start past it — start after end, a collapsed caret in the wrong row.
test("a box in the next row is nobody's business", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>REPLACED other words</li>' +
      '<li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>​</li></ul>',
    "hybrid"
  );
  const text = e._visualEl.querySelector("li").lastChild;
  const r = document.createRange();
  r.setStart(text, 0);
  r.setEnd(text, 8);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(
    e._selectionHoldsTaskBox(),
    false,
    "a text-anchored selection in row 1 holds no box, next row or not"
  );

  e._shrinkSelectionPastTaskBoxes();
  const after = window.getSelection().getRangeAt(0);
  assert.equal(after.startContainer, text, "and the shrink has nothing to do");
  assert.equal(String(window.getSelection()), "REPLACED");

  e.cleanup();
});

test("a box genuinely inside the range is still caught", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>does yes</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const r = document.createRange();
  r.setStart(li, 0);
  r.setEnd(li.lastChild, 4);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(e._selectionHoldsTaskBox(), true, "the double-click shape still detected");

  e.cleanup();
});

// The reporter's lone-word shape: the double-click grabbed the revealed
// "- [ ] " marker along with the word. Shrinking past the box alone left the
// marker span in the range — his engine refused the edit; the manual edit
// here destroyed the whole row.
test("a selection holding the revealed marker shrinks to the label", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li data-leaf-source="li" class="leaf-task" data-checked="false">' +
      '<span class="leaf-task-box" contenteditable="false"></span>' +
      '<span class="leaf-source-marker leaf-list-marker">- [ ] </span>word</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const r = document.createRange();
  r.selectNodeContents(li);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(e._selectionHoldsTaskBox(), true, "chrome in range — the takeover's case");

  e._shrinkSelectionPastTaskBoxes();
  assert.equal(String(window.getSelection()), "word",
    "only the label stays selected — the marker and box survive a replacement");

  e.cleanup();
});

test("a start inside the marker span steps out of it", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li data-leaf-source="li" class="leaf-task" data-checked="false">' +
      '<span class="leaf-task-box" contenteditable="false"></span>' +
      '<span class="leaf-source-marker leaf-list-marker">- [ ] </span>word</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const markerText = li.querySelector(".leaf-source-marker").firstChild;
  const r = document.createRange();
  r.setStart(markerText, 2);
  r.setEnd(li.lastChild, 4);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(e._selectionHoldsTaskBox(), true);
  e._shrinkSelectionPastTaskBoxes();
  assert.equal(String(window.getSelection()), "word");

  e.cleanup();
});

test("inline bold markers are body content, not chrome", { skip: dom.skip }, () => {
  const e = dom.editor(
    '<ul><li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>' +
      '<strong><span class="leaf-source-marker">**</span>bold<span class="leaf-source-marker">**</span></strong> word</li></ul>',
    "hybrid"
  );
  const li = e._visualEl.querySelector("li");
  const strong = li.querySelector("strong");
  const r = document.createRange();
  r.selectNodeContents(strong);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(
    e._selectionHoldsTaskBox(),
    false,
    "a replacement may legitimately eat the ** around bold"
  );

  e.cleanup();
});

// ---------------------------------------------------------------------------
// Selecting the WHOLE row means replacing the whole row
// ---------------------------------------------------------------------------
//
// Triple-click grabs "- [ ] test test test" — marker and all — and typing
// should leave a plain line of the typed text, the way Obsidian treats a
// selected marker as just more text. Anything less than the whole row keeps
// the checkbox and replaces only what was selected.

function fullRowSelected(e) {
  const li = e._visualEl.querySelector("li.leaf-task");
  const r = document.createRange();
  r.selectNodeContents(li);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
  return li;
}

const TASK_LI =
  '<li class="leaf-task" data-checked="false"><span class="leaf-task-box" contenteditable="false"></span>test</li>';

test("the only row: the list itself becomes the paragraph", { skip: dom.skip }, () => {
  const e = dom.editor("<ul>" + TASK_LI + "</ul>", "hybrid");
  fullRowSelected(e);

  assert.equal(e._replaceWholeListRow("R"), true);
  assert.equal(e._visualEl.querySelector("ul"), null, "an emptied list is not a list");
  assert.equal(e._visualEl.querySelector("p").textContent, "R");

  e.cleanup();
});

test("the first row: the paragraph lands before the list", { skip: dom.skip }, () => {
  const e = dom.editor("<ul>" + TASK_LI + "<li>stays</li></ul>", "hybrid");
  fullRowSelected(e);

  assert.equal(e._replaceWholeListRow("R"), true);
  const kids = e._visualEl.children;
  assert.equal(kids[0].tagName, "P");
  assert.equal(kids[1].tagName, "UL");
  assert.equal(kids[1].textContent, "stays");

  e.cleanup();
});

test("a mid-list row splits the list around the paragraph", { skip: dom.skip }, () => {
  const e = dom.editor("<ul><li>above</li>" + TASK_LI + "<li>below</li></ul>", "hybrid");
  fullRowSelected(e);

  assert.equal(e._replaceWholeListRow("R"), true);
  const kids = e._visualEl.children;
  assert.equal(
    [kids[0].tagName, kids[1].tagName, kids[2].tagName].join(","),
    "UL,P,UL",
    "the rows below keep their list"
  );
  assert.equal(kids[0].textContent, "above");
  assert.equal(kids[2].textContent, "below");

  e.cleanup();
});

test("less than the whole row falls through to the label path", { skip: dom.skip }, () => {
  const e = dom.editor("<ul>" + TASK_LI + "</ul>", "hybrid");
  const li = e._visualEl.querySelector("li");
  const text = li.lastChild;
  const r = document.createRange();
  r.setStart(text, 0);
  r.setEnd(text, 4);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(e._replaceWholeListRow("R"), false, "the word is not the row");
  assert.ok(e._visualEl.querySelector("li.leaf-task"), "and nothing was replaced");

  e.cleanup();
});

test("the takeover consults the whole-row branch before shrinking", { skip: dom.skip }, () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("../../priv/static/assets/leaf.js"), "utf8");
  const gate = src.slice(
    src.indexOf("_setupCommandWindow: function"),
    src.indexOf("_setupTypingDiagnostics: function")
  );

  const wholeRow = gate.indexOf("_replaceWholeListRow(e.data");
  const shrink = gate.indexOf("_shrinkSelectionPastTaskBoxes()");
  assert.ok(wholeRow >= 0, "the whole-row branch must be wired in");
  assert.ok(wholeRow < shrink, "and asked FIRST — the shrink is the lesser intent");
});

// "- [ ]", "- ", "3. " — one rule. A wholly selected row of ANY list kind is
// replaced whole, chrome and all.

function markedLi(marker, label) {
  return (
    '<li><span class="leaf-source-marker leaf-list-marker">' +
    marker +
    "</span>" +
    label +
    "</li>"
  );
}

function selectWholeLi(e) {
  const li = e._visualEl.querySelector("ul li, ol li");
  const r = document.createRange();
  r.selectNodeContents(li);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
  return li;
}

test("a whole bullet row goes the way of the checkbox row", { skip: dom.skip }, () => {
  const e = dom.editor("<ul>" + markedLi("- ", "word") + "</ul>", "hybrid");
  selectWholeLi(e);

  assert.equal(e._replaceWholeListRow("R"), true);
  assert.equal(e._visualEl.querySelector("ul"), null);
  assert.equal(e._visualEl.querySelector("p").textContent, "R");

  e.cleanup();
});

test("a numbered tail keeps its numbers after the split", { skip: dom.skip }, () => {
  const e = dom.editor(
    "<ol><li>one</li>" + markedLi("2. ", "two") + "<li>three</li></ol>",
    "hybrid"
  );
  const li = e._visualEl.querySelectorAll("ol li")[1];
  const r = document.createRange();
  r.selectNodeContents(li);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(e._replaceWholeListRow("R"), true);
  const kids = e._visualEl.children;
  assert.equal([kids[0].tagName, kids[1].tagName, kids[2].tagName].join(","), "OL,P,OL");
  assert.equal(kids[2].getAttribute("start"), "3", "the row below is still number three");
  assert.equal(kids[2].textContent, "three");

  e.cleanup();
});

test("a bullet label alone is still just a label", { skip: dom.skip }, () => {
  const e = dom.editor("<ul>" + markedLi("- ", "word") + "</ul>", "hybrid");
  const text = e._visualEl.querySelector("li").lastChild;
  const r = document.createRange();
  r.setStart(text, 0);
  r.setEnd(text, 4);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);

  assert.equal(e._replaceWholeListRow("R"), false, "no chrome in hand, no row replaced");
  assert.ok(e._visualEl.querySelector("ul li"), "the bullet row survives");

  e.cleanup();
});
