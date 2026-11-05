"use strict";

// The insert pickers: image/video requests to the host, the image-URL dialog,
// the host's insert_image command, and the emoji / symbol pickers.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

// An editor whose hook root holds a toolbar and the surface, like the
// rendered component.
function pickerEditor(html, mode = "visual") {
  const e = dom.editor(html || "<p>hello world</p>", mode);
  const root = document.createElement("div");
  const toolbar = document.createElement("div");
  toolbar.setAttribute("data-visual-toolbar", "");
  toolbar.innerHTML =
    '<button data-toolbar-action="emoji"></button>' +
    '<button data-toolbar-action="symbols"></button>' +
    '<button data-image-split-btn></button>';
  e._visualEl.parentNode.insertBefore(root, e._visualEl);
  root.appendChild(toolbar);
  root.appendChild(e._visualEl);
  e.el = root;
  const cleanup = e.cleanup;
  e.cleanup = () => {
    cleanup();
    root.remove();
    document.querySelectorAll(".leaf-image-url-dialog, .leaf-image-url-backdrop").forEach((n) => n.remove());
  };
  e.pushed = [];
  e.pushEventTo = (_el, event, payload) => e.pushed.push([event, payload]);
  e.visualPushes = 0;
  e._debouncedPushVisualChange = () => e.visualPushes++;
  return e;
}

// jsdom has no editing commands; insertText at the selection is enough here.
function stubInsertText() {
  document.execCommand = (cmd, _ui, value) => {
    if (cmd !== "insertText") return false;
    const sel = window.getSelection();
    const r = sel.getRangeAt(0);
    r.deleteContents();
    const t = document.createTextNode(value);
    r.insertNode(t);
    r.setStartAfter(t);
    r.collapse(true);
    sel.removeAllRanges();
    sel.addRange(r);
    return true;
  };
}

// The clickable emoji cells of a picker.
const cells = (picker) =>
  Array.from(picker.querySelectorAll("span")).filter((s) => s.style.cursor === "pointer");

function caretAt(node, offset) {
  const r = document.createRange();
  r.setStart(node, offset);
  r.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
}

// --------------------------------------------------------------------------
// Image / video requests
// --------------------------------------------------------------------------

test("insert image with an upload handler asks the host", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._hasUpload = true;
  e._execToolbarAction("insert-image");
  assert.deepEqual(e.pushed[0], ["insert_request", { editor_id: "test-editor", type: "image" }]);
  e.cleanup();
});

test("insert image without one opens the URL dialog instead", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._hasUpload = false;
  e._execToolbarAction("insert-image");
  assert.ok(document.querySelector(".leaf-image-url-dialog"));
  assert.ok(!e.pushed.some(([ev]) => ev === "insert_request"));
  e.cleanup();
});

test("insert video asks the host for a video", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._execToolbarAction("insert-video");
  assert.deepEqual(e.pushed[0], ["insert_request", { editor_id: "test-editor", type: "video" }]);
  e.cleanup();
});

test("denied images and video send no request", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._hasUpload = true;
  e._denyImages = true;
  e._denyVideo = true;
  for (const a of ["insert-image", "insert-image-upload", "insert-image-url", "insert-video"]) {
    e._execToolbarAction(a);
  }
  assert.deepEqual(e.pushed, []);
  assert.equal(document.querySelector(".leaf-image-url-dialog"), null);
  e.cleanup();
});

test("readonly sends no request", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._readonly = true;
  e._hasUpload = true;
  e._execToolbarAction("insert-image");
  e._execToolbarAction("insert-video");
  assert.deepEqual(e.pushed, []);
  e.cleanup();
});

// --------------------------------------------------------------------------
// Image URL dialog
// --------------------------------------------------------------------------

function openDialog(e) {
  e._openImageUrlDialog();
  const dialog = document.querySelector(".leaf-image-url-dialog");
  const [url, alt] = dialog.querySelectorAll("input");
  return { dialog, url, alt, insert: dialog.querySelector(".leaf-image-url-insert") };
}

test("the dialog inserts a safe URL with its alt text", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._insertImageByUrl = (url, alt) => (e.inserted = [url, alt]);
  const d = openDialog(e);
  d.url.value = "https://img.example/a.png";
  d.alt.value = "  a cat ";
  d.insert.click();
  assert.deepEqual(e.inserted, ["https://img.example/a.png", "a cat"]);
  assert.equal(document.querySelector(".leaf-image-url-dialog"), null, "closed");
  e.cleanup();
});

test("the dialog refuses an unsafe URL and stays open", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._insertImageByUrl = () => (e.inserted = true);
  const d = openDialog(e);
  for (const bad of ["javascript:alert(1)", "data:image/svg+xml,<svg onload=alert(1)>", ""]) {
    d.url.value = bad;
    d.insert.click();
  }
  assert.equal(e.inserted, undefined);
  assert.ok(document.querySelector(".leaf-image-url-dialog"));
  e.cleanup();
});

test("Enter inserts, Escape closes", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._insertImageByUrl = (url) => (e.inserted = url);
  let d = openDialog(e);
  d.url.value = "/a.png";
  d.url.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  assert.equal(e.inserted, "/a.png");

  d = openDialog(e);
  d.alt.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  assert.equal(document.querySelector(".leaf-image-url-dialog"), null);
  e.cleanup();
});

test("the dialog tells the host media UI opened and closed", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._openImageUrlDialog();
  const opened = e.pushed.filter(([ev]) => ev === "media_ui_opened").length;
  document.querySelector(".leaf-image-url-backdrop").click();
  assert.equal(opened, 1);
  assert.equal(e.pushed[e.pushed.length - 1][0], "media_ui_closed");
  assert.equal(document.querySelector(".leaf-image-url-dialog"), null);
  e.cleanup();
});

test(
  "opening the dialog does not report a close first",
  { skip: dom.skip },
  () => {
    const e = pickerEditor();
    e._openImageUrlDialog();
    assert.deepEqual(e.pushed.map(([ev]) => ev), ["media_ui_opened"]);
    e.cleanup();
  }
);

// --------------------------------------------------------------------------
// The host's insert_image command
// --------------------------------------------------------------------------

test("insert_image from the host inserts a safe URL", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._insertImageByUrl = (url, alt) => (e.inserted = [url, alt]);
  e._handleCommand({ action: "insert_image", url: "https://img.example/a.png", alt: "x" });
  assert.deepEqual(e.inserted, ["https://img.example/a.png", "x"]);
  e.cleanup();
});

test("insert_image refuses script and SVG URLs", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._insertImageByUrl = () => (e.inserted = true);
  e._handleCommand({ action: "insert_image", url: "javascript:alert(1)" });
  e._handleCommand({ action: "insert_image", url: "data:image/svg+xml;base64,PHN2Zz4=" });
  assert.equal(e.inserted, undefined);
  e.cleanup();
});

// --------------------------------------------------------------------------
// Emoji and symbol pickers
// --------------------------------------------------------------------------

test("the emoji picker inserts at the caret it was opened from", { skip: dom.skip }, () => {
  const e = pickerEditor("<p>hello world</p>");
  stubInsertText();
  const text = e._visualEl.querySelector("p").firstChild;
  caretAt(text, 5);
  e._openEmojiPicker();
  const picker = e.el.querySelector(".leaf-emoji-picker");
  assert.ok(picker, "picker open");

  // Focus wanders to the search box; the saved caret must still win.
  caretAt(document.body, 0);
  const first = cells(picker)[0];
  first.click();
  const emoji = first.textContent;
  assert.equal(e._currentMarkdown().trim(), "hello" + emoji + " world");
  assert.equal(e.visualPushes, 1);
  e._closeEmojiPicker();
  e.cleanup();
});

test("emoji search filters by keyword and says when nothing matches", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._openEmojiPicker();
  const picker = e.el.querySelector(".leaf-emoji-picker");
  const search = picker.querySelector("input");
  const all = cells(picker).length;

  search.value = "heart";
  search.dispatchEvent(new window.Event("input"));
  const hits = cells(picker).length;
  assert.ok(hits > 0 && hits < all, `heart matched ${hits} of ${all}`);

  search.value = "zzzzqqq";
  search.dispatchEvent(new window.Event("input"));
  assert.match(picker.textContent, /No emoji found/);
  e._closeEmojiPicker();
  e.cleanup();
});

test("the emoji button toggles the picker", { skip: dom.skip }, () => {
  const e = pickerEditor();
  e._openEmojiPicker();
  e._openEmojiPicker();
  assert.equal(e.el.querySelector(".leaf-emoji-picker"), null);
  e.cleanup();
});

test("a stale selection outside the editor is not restored for the insert", { skip: dom.skip }, () => {
  const e = pickerEditor("<p>keep this</p>");
  const outside = document.createElement("p");
  outside.textContent = "elsewhere";
  document.body.appendChild(outside);
  caretAt(outside.firstChild, 3);
  e._openEmojiPicker();
  assert.equal(e._savedRange, null);
  e._closeEmojiPicker();
  outside.remove();
  e.cleanup();
});

test("in markdown mode an emoji goes through the textarea's insert helper", { skip: dom.skip }, () => {
  const e = pickerEditor("<p>x</p>", "markdown");
  let got = null;
  window["markdownEditorInsert_test_editor_markdown"] = (s) => (got = s);
  e._insertEmoji("🎉");
  assert.equal(got, "🎉");
  delete window["markdownEditorInsert_test_editor_markdown"];
  e.cleanup();
});

test("a symbol inserts and closes the symbol picker", { skip: dom.skip }, () => {
  const e = pickerEditor("<p>ab</p>");
  stubInsertText();
  caretAt(e._visualEl.querySelector("p").firstChild, 1);
  e._openSymbolPicker();
  const cell = Array.from(document.querySelectorAll("span")).find((s) => s.textContent === "→");
  cell.click();
  assert.equal(e._currentMarkdown().trim(), "a→b");
  assert.equal(e._symbolPicker, null, "closed");
  e.cleanup();
});

test("insert date writes today's date", { skip: dom.skip }, () => {
  const e = pickerEditor("<p>on </p>");
  stubInsertText();
  const t = e._visualEl.querySelector("p").firstChild;
  caretAt(t, 3);
  e._openSymbolPicker();
  Array.from(document.querySelectorAll("button")).find((b) => b.textContent === "Insert date").click();
  assert.equal(e._currentMarkdown().trim(), "on " + new Date().toLocaleDateString());
  e.cleanup();
});
