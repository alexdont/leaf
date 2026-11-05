"use strict";

// Tables: what the toolbar's table actions do to the DOM, and what the
// serializer writes back. Markdown tables are lossy in known ways (one header
// row, alignment per column, no block content in a cell), so most of these
// pin the round-trip rules rather than the markup.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

const TABLE =
  "<table><thead><tr><th>H1</th><th>H2</th></tr></thead>" +
  "<tbody><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></tbody></table>";

function tableEditor(html) {
  const e = dom.editor(html || TABLE, "visual");
  e.pushed = 0;
  e._debouncedPushVisualChange = () => e.pushed++;
  return e;
}

// Put the caret inside the cell at [row][col] (rows across thead + tbody).
function caretInCell(e, row, col) {
  const cell = e._visualEl.querySelectorAll("tr")[row].children[col];
  const range = document.createRange();
  range.setStart(cell.firstChild || cell, 0);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  return cell;
}

const md = (e) => e._currentMarkdown().trim();
const grid = (e) =>
  Array.from(e._visualEl.querySelectorAll("tr")).map((tr) =>
    Array.from(tr.children).map((c) => c.tagName.toLowerCase() + ":" + c.textContent)
  );

// --------------------------------------------------------------------------
// Serialization
// --------------------------------------------------------------------------

test("a table serializes as a GFM table", { skip: dom.skip }, () => {
  const e = tableEditor();
  assert.equal(md(e), "| H1 | H2 |\n| --- | --- |\n| a | b |\n| c | d |");
  e.cleanup();
});

test("alignment comes from the header row: data-align or an inline style", { skip: dom.skip }, () => {
  const e = tableEditor(
    "<table><thead><tr><th data-align=\"left\">L</th><th style=\"text-align: center\">C</th>" +
      "<th data-align=\"right\">R</th><th>N</th></tr></thead>" +
      "<tbody><tr><td>1</td><td>2</td><td>3</td><td>4</td></tr></tbody></table>"
  );
  assert.equal(md(e).split("\n")[1], "| :--- | :---: | ---: | --- |");
  e.cleanup();
});

test("a pipe in a cell is escaped so it does not split the cell", { skip: dom.skip }, () => {
  const e = tableEditor("<table><tr><th>a|b</th></tr><tr><td>x | y</td></tr></table>");
  assert.equal(md(e), "| a\\|b |\n| --- |\n| x \\| y |");
  e.cleanup();
});

test("a line break in a cell is written as <br>", { skip: dom.skip }, () => {
  const e = tableEditor("<table><tr><th>h</th></tr><tr><td>one<br>two</td></tr></table>");
  assert.equal(md(e).split("\n")[2], "| one<br>two |");
  e.cleanup();
});

test("inline formatting and literal syntax in a cell survive", { skip: dom.skip }, () => {
  const e = tableEditor(
    "<table><tr><th>h</th></tr><tr><td><strong>bold</strong> and *stars*</td></tr></table>"
  );
  assert.equal(md(e).split("\n")[2], "| **bold** and \\*stars\\* |");
  e.cleanup();
});

test("an empty cell is an empty column, not a missing one", { skip: dom.skip }, () => {
  const e = tableEditor("<table><tr><th>a</th><th>b</th></tr><tr><td><br></td><td>x</td></tr></table>");
  assert.equal(md(e).split("\n")[2], "|  | x |");
  e.cleanup();
});

// --------------------------------------------------------------------------
// Toolbar actions
// --------------------------------------------------------------------------

test("add row: below the caret's row, as wide as the table", { skip: dom.skip }, () => {
  const e = tableEditor();
  caretInCell(e, 1, 0);
  e._tableAddRow();
  assert.deepEqual(grid(e).map((r) => r.join(",")), [
    "th:H1,th:H2",
    "td:a,td:b",
    "td:,td:",
    "td:c,td:d",
  ]);
  e.cleanup();
});

test("add row from the header row puts it first in the body", { skip: dom.skip }, () => {
  const e = tableEditor();
  caretInCell(e, 0, 1);
  e._tableAddRow();
  const rows = grid(e);
  assert.equal(rows[1].join(","), "td:,td:");
  assert.equal(rows[0].join(","), "th:H1,th:H2", "the header stays the header");
  e.cleanup();
});

test("remove row: the body row goes, the header row cannot", { skip: dom.skip }, () => {
  const e = tableEditor();
  caretInCell(e, 2, 0);
  e._tableRemoveRow();
  assert.deepEqual(grid(e).map((r) => r.join(",")), ["th:H1,th:H2", "td:a,td:b"]);

  caretInCell(e, 0, 0);
  e._tableRemoveRow();
  assert.equal(grid(e).length, 2, "removing the header row is refused");
  e.cleanup();
});

test("removing the only row removes the table", { skip: dom.skip }, () => {
  const e = tableEditor("<table><tbody><tr><td>only</td></tr></tbody></table><p>after</p>");
  caretInCell(e, 0, 0);
  e._tableRemoveRow();
  assert.equal(e._visualEl.querySelector("table"), null);
  assert.equal(md(e), "after");
  e.cleanup();
});

test("add column: after the caret's column, th in the header, td below", { skip: dom.skip }, () => {
  const e = tableEditor();
  caretInCell(e, 1, 0);
  e._tableAddCol();
  assert.deepEqual(grid(e).map((r) => r.join(",")), [
    "th:H1,th:,th:H2",
    "td:a,td:,td:b",
    "td:c,td:,td:d",
  ]);
  assert.equal(md(e).split("\n")[1], "| --- | --- | --- |");
  e.cleanup();
});

test("remove column takes the caret's column from every row", { skip: dom.skip }, () => {
  const e = tableEditor();
  caretInCell(e, 2, 1);
  e._tableRemoveCol();
  assert.equal(md(e), "| H1 |\n| --- |\n| a |\n| c |");
  e.cleanup();
});

test("removing the only column removes the table", { skip: dom.skip }, () => {
  const e = tableEditor("<table><tr><th>h</th></tr><tr><td>x</td></tr></table><p>after</p>");
  caretInCell(e, 1, 0);
  e._tableRemoveCol();
  assert.equal(e._visualEl.querySelector("table"), null);
  e.cleanup();
});

test("align stamps the whole column and reaches the separator row", { skip: dom.skip }, () => {
  const e = tableEditor();
  caretInCell(e, 2, 1);
  e._tableSetAlign("center");
  const col = Array.from(e._visualEl.querySelectorAll("tr")).map((tr) =>
    tr.children[1].getAttribute("data-align")
  );
  assert.deepEqual(col, ["center", "center", "center"]);
  assert.equal(md(e).split("\n")[1], "| --- | :---: |");
  assert.equal(e.pushed, 1);

  e._tableSetAlign("");
  assert.equal(md(e).split("\n")[1], "| --- | --- |");
  e.cleanup();
});

test("toggle header flips the first row between th and td and keeps alignment", { skip: dom.skip }, () => {
  const e = tableEditor(
    "<table><thead><tr><th data-align=\"right\">H1</th><th>H2</th></tr></thead>" +
      "<tbody><tr><td>a</td><td>b</td></tr></tbody></table>"
  );
  caretInCell(e, 1, 0);
  e._tableToggleHeader();
  let first = e._visualEl.querySelector("tr");
  assert.deepEqual(Array.from(first.children).map((c) => c.tagName), ["TD", "TD"]);
  assert.equal(first.children[0].getAttribute("data-align"), "right");

  e._tableToggleHeader();
  first = e._visualEl.querySelector("tr");
  assert.deepEqual(Array.from(first.children).map((c) => c.tagName), ["TH", "TH"]);
  assert.equal(md(e).split("\n")[1], "| ---: | --- |");
  e.cleanup();
});

test("table actions do nothing with the caret outside a table", { skip: dom.skip }, () => {
  const e = tableEditor("<p>no table</p>" + TABLE);
  const p = e._visualEl.querySelector("p");
  dom.caretAtEndOf(p);
  const before = e._visualEl.innerHTML;
  e._tableAddRow();
  e._tableRemoveRow();
  e._tableAddCol();
  e._tableRemoveCol();
  e._tableSetAlign("left");
  e._tableToggleHeader();
  assert.equal(e._visualEl.innerHTML, before);
  e.cleanup();
});

test("the table toolbar action inserts a 2x2 table with a paragraph after it", { skip: dom.skip }, () => {
  const e = tableEditor("<p>x</p>");
  let html = null;
  document.execCommand = (cmd, _ui, value) => {
    if (cmd === "insertHTML") html = value;
    return true;
  };
  e._insertTable();
  const box = document.createElement("div");
  box.innerHTML = html;
  assert.equal(box.querySelectorAll("th").length, 2);
  assert.equal(box.querySelectorAll("td").length, 4);
  assert.equal(box.lastElementChild.tagName, "P", "a paragraph to type into after the table");
  e.cleanup();
});

// --------------------------------------------------------------------------
// Pasting tabular text
// --------------------------------------------------------------------------

function pasteTabular(text) {
  const e = tableEditor("<p>x</p>");
  let html = null;
  document.execCommand = (cmd, _ui, value) => {
    if (cmd === "insertHTML") html = value;
    return true;
  };
  const handled = e._maybePasteTabular(text);
  e.cleanup();
  return { handled, html };
}

test("tab-separated text pastes as a table with the first line as header", { skip: dom.skip }, () => {
  const { handled, html } = pasteTabular("Name\tAge\nAda\t36\nAlan\t41\n");
  assert.equal(handled, true);
  const box = document.createElement("div");
  box.innerHTML = html;
  assert.deepEqual(Array.from(box.querySelectorAll("th")).map((c) => c.textContent), ["Name", "Age"]);
  assert.deepEqual(Array.from(box.querySelectorAll("td")).map((c) => c.textContent), ["Ada", "36", "Alan", "41"]);
});

test("pasted cell text is escaped, not parsed as markup", { skip: dom.skip }, () => {
  const { html } = pasteTabular("a\tb\n<img src=x onerror=alert(1)>\t&amp;");
  const box = document.createElement("div");
  box.innerHTML = html;
  assert.equal(box.querySelector("img"), null);
  assert.equal(box.querySelectorAll("td")[0].textContent, "<img src=x onerror=alert(1)>");
  assert.equal(box.querySelectorAll("td")[1].textContent, "&amp;");
});

test("ragged tab rows are padded to the widest row", { skip: dom.skip }, () => {
  const { html } = pasteTabular("a\tb\tc\n1\t2");
  const box = document.createElement("div");
  box.innerHTML = html;
  assert.equal(box.querySelectorAll("tbody tr")[0].children.length, 3);
});

test("comma text is a table only when every line has the same 3+ fields", { skip: dom.skip }, () => {
  assert.equal(pasteTabular("a,b,c\n1,2,3").handled, true);
  assert.equal(pasteTabular("a,b\n1,2").handled, false, "two columns of commas is prose");
  assert.equal(
    pasteTabular("Well, I said, yes.\nAnd then, no.").handled,
    false,
    "prose with commas is not hijacked"
  );
  assert.equal(pasteTabular("one line, no, table").handled, false, "a single line is not a table");
});
