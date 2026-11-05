"use strict";

// The link popover: a click on a link in visual mode shows its URL with edit
// and remove; hybrid and markdown modes edit the source instead.
//
// Run: mix test.js

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

function popoverEditor(html, mode = "visual") {
  const e = dom.editor(html, mode);
  // The hook root wraps the editing surface (the popover is appended to the
  // root, never into the content); the shared helper makes them one element.
  const root = document.createElement("div");
  e._visualEl.parentNode.insertBefore(root, e._visualEl);
  root.appendChild(e._visualEl);
  e.el = root;
  const cleanup = e.cleanup;
  e.cleanup = () => {
    cleanup();
    root.remove();
  };
  const proto = Object.getPrototypeOf(e);
  e._dismissLinkPopover = proto._dismissLinkPopover;
  e._dismissImagePopover = () => {};
  e._showImagePopover = (img) => (e.imageShown = img);
  e.pushed = 0;
  e._debouncedPushVisualChange = () => e.pushed++;
  proto._setupLinkPopover.call(e);
  return e;
}

function click(el, init = {}) {
  const ev = new window.MouseEvent("click", { bubbles: true, cancelable: true, ...init });
  el.dispatchEvent(ev);
  return ev;
}

const popover = (e) => e.el.querySelector(".leaf-link-popover");

test("clicking a link in visual mode shows its URL and does not navigate", { skip: dom.skip }, () => {
  const e = popoverEditor('<p>see <a href="https://a.example/x">this</a></p>');
  const ev = click(e._visualEl.querySelector("a"));

  assert.ok(ev.defaultPrevented, "no navigation");
  assert.ok(popover(e), "popover shown");
  assert.equal(popover(e).querySelector("a").getAttribute("href"), "https://a.example/x");
  assert.equal(popover(e).querySelector("a").getAttribute("rel"), "noopener");
  e.cleanup();
});

test("a click on text inside a link's formatting still finds the link", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="/in"><strong>bold link</strong></a></p>');
  click(e._visualEl.querySelector("strong"));
  assert.equal(popover(e).querySelector("a").getAttribute("href"), "/in");
  e.cleanup();
});

test("a link with no href says so", { skip: dom.skip }, () => {
  const e = popoverEditor("<p><a>bare</a></p>");
  click(e._visualEl.querySelector("a"));
  assert.equal(popover(e).querySelector("a").textContent, "(no url)");
  e.cleanup();
});

test("hybrid mode never shows the popover, and a plain click does not navigate", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="https://a.example">x</a></p>', "hybrid");
  const ev = click(e._visualEl.querySelector("a"));
  assert.ok(ev.defaultPrevented);
  assert.equal(popover(e), null);

  const modClick = click(e._visualEl.querySelector("a"), { metaKey: true });
  assert.ok(!modClick.defaultPrevented, "cmd/ctrl-click is left to the browser");
  e.cleanup();
});

test("readonly shows nothing", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="https://a.example">x</a></p>');
  e._readonly = true;
  click(e._visualEl.querySelector("a"));
  assert.equal(popover(e), null);
  e.cleanup();
});

test("remove unwraps the link, keeps its text, and pushes", { skip: dom.skip }, () => {
  const e = popoverEditor('<p>see <a href="https://a.example"><em>this</em> one</a> now</p>');
  click(e._visualEl.querySelector("a"));
  popover(e).querySelector('button[title="Remove link"]').click();

  assert.equal(e._visualEl.querySelector("a"), null);
  assert.equal(e._currentMarkdown().trim(), "see *this* one now");
  assert.equal(popover(e), null, "popover closed");
  assert.equal(e.pushed, 1);
  e.cleanup();
});

function editWith(e, value) {
  e._openTextPrompt = (opts) => {
    e.promptValue = opts.value;
    opts.onSubmit(value);
  };
  popover(e).querySelector('button[title="Edit link"]').click();
}

test("edit offers the current URL and writes a new one", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="https://old.example">x</a></p>');
  click(e._visualEl.querySelector("a"));
  editWith(e, "  https://new.example/p  ");

  assert.equal(e.promptValue, "https://old.example");
  assert.equal(e._visualEl.querySelector("a").getAttribute("href"), "https://new.example/p");
  assert.equal(popover(e).querySelector("a").textContent, "https://new.example/p", "popover follows");
  assert.equal(e._currentMarkdown().trim(), "[x](https://new.example/p)");
  e.cleanup();
});

test("editing to an empty URL removes the link", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="https://old.example">x</a></p>');
  click(e._visualEl.querySelector("a"));
  editWith(e, "");
  assert.equal(e._visualEl.querySelector("a"), null);
  assert.equal(e._currentMarkdown().trim(), "x");
  e.cleanup();
});

test("an unsafe URL is refused and the old one kept", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="https://old.example">x</a></p>');
  click(e._visualEl.querySelector("a"));
  editWith(e, "javascript:alert(1)");
  assert.equal(e._visualEl.querySelector("a").getAttribute("href"), "https://old.example");
  e.cleanup();
});

test("clicking elsewhere in the editor or outside it closes the popover", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="/a">x</a> plain</p>');
  click(e._visualEl.querySelector("a"));
  click(e._visualEl.querySelector("p"));
  assert.equal(popover(e), null, "click on plain text closes it");

  click(e._visualEl.querySelector("a"));
  const outside = document.createElement("div");
  document.body.appendChild(outside);
  outside.dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true }));
  assert.equal(popover(e), null, "mousedown outside closes it");
  outside.remove();
  e.cleanup();
});

test("a mousedown inside the popover keeps it open", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="/a">x</a></p>');
  click(e._visualEl.querySelector("a"));
  popover(e).dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true }));
  assert.ok(popover(e));
  e.cleanup();
});

test("opening another link replaces the popover rather than stacking", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="/one">1</a> <a href="/two">2</a></p>');
  const links = e._visualEl.querySelectorAll("a");
  click(links[0]);
  click(links[1]);
  assert.equal(e.el.querySelectorAll(".leaf-link-popover").length, 1);
  assert.equal(popover(e).querySelector("a").getAttribute("href"), "/two");
  e.cleanup();
});

test("clicking an image opens the image popover instead", { skip: dom.skip }, () => {
  const e = popoverEditor('<p><a href="/a"><img src="/i.png" alt=""></a></p>');
  const img = e._visualEl.querySelector("img");
  click(img);
  assert.equal(e.imageShown, img);
  assert.equal(popover(e), null);
  e.cleanup();
});
