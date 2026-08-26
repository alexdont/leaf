"use strict";

// Obsidian-style `[[Target]]` links, client side.
//
// Two halves: turning the text into decoration spans, and resolving those
// targets against the host — only the host knows which notes exist.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

function wikiEditor(html, opts = {}) {
  const e = editor(html || "<p>x</p>", "hybrid");

  e._wikiLinks = true;
  e._hashtags = true;
  e._readonly = !!opts.readonly;
  e._editorId = "wl";
  e.pushed = [];
  e.pushEventTo = (_el, event, payload) => e.pushed.push({ event, payload });

  return e;
}

function decorate(e, text) {
  const box = document.createElement("div");
  e._textWithDecorations(text).forEach((n) => box.appendChild(n));
  return box;
}

// --------------------------------------------------------------------------
// Decoration
// --------------------------------------------------------------------------

test("a plain target becomes a link token", { skip }, () => {
  const e = wikiEditor();
  const box = decorate(e, "see [[Ideas]] here");
  const span = box.querySelector(".leaf-wikilink");

  assert.equal(span.getAttribute("data-leaf-wikilink"), "Ideas");
  assert.equal(span.textContent, "Ideas");
  assert.equal(box.textContent, "see Ideas here");
  e.cleanup();
});

test("an alias is shown, the target is kept", { skip }, () => {
  const e = wikiEditor();
  const span = decorate(e, "see [[Ideas|my notes]]").querySelector(".leaf-wikilink");

  assert.equal(span.getAttribute("data-leaf-wikilink"), "Ideas");
  assert.equal(span.textContent, "my notes");
  e.cleanup();
});

test("a heading is carried separately", { skip }, () => {
  const e = wikiEditor();
  const span = decorate(e, "see [[Ideas#Later]]").querySelector(".leaf-wikilink");

  assert.equal(span.getAttribute("data-leaf-wikilink"), "Ideas");
  assert.equal(span.getAttribute("data-leaf-wikilink-heading"), "Later");
  e.cleanup();
});

test("a heading is not mistaken for a hashtag", { skip }, () => {
  // Wiki links are matched BEFORE hashtags for exactly this: running the
  // hashtag pass first would tokenise `#Later` and leave the link unmatched.
  const e = wikiEditor();
  const box = decorate(e, "[[Note#Section]] text");

  assert.equal(box.querySelectorAll(".leaf-hashtag").length, 0);
  assert.equal(box.querySelectorAll(".leaf-wikilink").length, 1);
  e.cleanup();
});

test("links and hashtags coexist", { skip }, () => {
  const e = wikiEditor();
  const box = decorate(e, "mixed [[Ideas]] and #tag");

  assert.equal(box.querySelectorAll(".leaf-wikilink").length, 1);
  assert.equal(box.querySelectorAll(".leaf-hashtag").length, 1);
  e.cleanup();
});

test("nothing happens when the host has not opted in", { skip }, () => {
  const e = wikiEditor();
  e._wikiLinks = false;

  assert.equal(decorate(e, "see [[Ideas]]").querySelectorAll(".leaf-wikilink").length, 0);
  e.cleanup();
});

// --------------------------------------------------------------------------
// Serialization — the part that can destroy a document
// --------------------------------------------------------------------------

test("a link serializes back to its source, not its label", { skip }, () => {
  // The span shows the ALIAS, so serializing its text — which is what an
  // undecorated span does, and what hashtags rely on — would write `my notes`
  // into the document and lose the link entirely.
  const e = wikiEditor();
  const p = e._visualEl.children[0];

  p.innerHTML = "";
  e._textWithDecorations("see [[Ideas|my notes]] and #tag").forEach((n) => p.appendChild(n));

  assert.equal(e._currentMarkdown(), "see [[Ideas|my notes]] and #tag");
  e.cleanup();
});

test("a plain link round-trips unchanged", { skip }, () => {
  const e = wikiEditor();
  const p = e._visualEl.children[0];

  p.innerHTML = "";
  e._textWithDecorations("see [[Ideas]] here").forEach((n) => p.appendChild(n));

  assert.equal(e._currentMarkdown(), "see [[Ideas]] here");
  e.cleanup();
});

// --------------------------------------------------------------------------
// Resolution
// --------------------------------------------------------------------------

const LINKS =
  '<p><span class="leaf-wikilink" data-leaf-wikilink="Ideas" data-leaf-wikilink-raw="[[Ideas]]">Ideas</span> ' +
  '<span class="leaf-wikilink" data-leaf-wikilink="Other" data-leaf-wikilink-raw="[[Other]]">Other</span> ' +
  '<span class="leaf-wikilink" data-leaf-wikilink="Ideas" data-leaf-wikilink-raw="[[Ideas]]">Ideas</span></p>';

test("each distinct target is asked for once", { skip }, () => {
  // A note usually links the same target many times; one request per
  // occurrence would be a request storm.
  const e = wikiEditor(LINKS);

  e._resolveWikiLinks();

  assert.equal(e.pushed.length, 1);
  assert.equal(e.pushed[0].event, "resolve_links");
  assert.deepEqual(e.pushed[0].payload.targets, ["Ideas", "Other"]);
  e.cleanup();
});

test("an answer marks every occurrence", { skip }, () => {
  const e = wikiEditor(LINKS);

  e._resolveWikiLinks();
  e._onWikiLinkTargets({
    seq: 1,
    targets: { Ideas: { href: "/notes/abc", exists: true }, Other: { href: null, exists: false } },
  });

  const spans = e._visualEl.querySelectorAll("[data-leaf-wikilink]");

  assert.equal(spans[0].getAttribute("data-leaf-wikilink-exists"), "true");
  assert.equal(spans[0].getAttribute("data-leaf-wikilink-href"), "/notes/abc");
  assert.equal(spans[1].getAttribute("data-leaf-wikilink-exists"), "false");
  assert.equal(spans[2].getAttribute("data-leaf-wikilink-exists"), "true");
  e.cleanup();
});

test("an answered target is not asked for again", { skip }, () => {
  const e = wikiEditor(LINKS);

  e._resolveWikiLinks();
  e._onWikiLinkTargets({ seq: 1, targets: { Ideas: { exists: true }, Other: { exists: false } } });
  e.pushed = [];
  e._resolveWikiLinks();

  assert.equal(e.pushed.length, 0);
  e.cleanup();
});

test("an answer a later edit superseded is dropped", { skip }, () => {
  // Typing routinely outruns a server round trip; the same guard the
  // suggestion protocol uses.
  const e = wikiEditor(LINKS);
  e._wikiLinkSeq = 5;

  e._onWikiLinkTargets({ seq: 2, targets: { Ideas: { href: "/stale", exists: true } } });

  assert.equal(
    e._visualEl.querySelector("[data-leaf-wikilink]").getAttribute("data-leaf-wikilink-href"),
    null
  );
  e.cleanup();
});

// --------------------------------------------------------------------------
// Clicking
// --------------------------------------------------------------------------

function clickFirstLink(e, mods) {
  const span = e._visualEl.querySelector("[data-leaf-wikilink]");
  const event = new window.MouseEvent("click", { bubbles: true, cancelable: true, ...mods });

  Object.defineProperty(event, "target", { value: span });
  e._onWikiLinkClick(event);

  return e.pushed.filter((p) => p.event === "link_clicked");
}

test("editing: a bare click places the caret rather than following", { skip }, () => {
  const e = wikiEditor(LINKS);

  assert.equal(clickFirstLink(e, {}).length, 0);
  e.cleanup();
});

test("editing: ctrl-click follows, as in Obsidian", { skip }, () => {
  const e = wikiEditor(LINKS);
  const clicks = clickFirstLink(e, { ctrlKey: true });

  assert.equal(clicks.length, 1);
  assert.equal(clicks[0].payload.target, "Ideas");
  e.cleanup();
});

test("read-only: a plain click follows, since no caret competes", { skip }, () => {
  const e = wikiEditor(LINKS, { readonly: true });

  assert.equal(clickFirstLink(e, {}).length, 1);
  e.cleanup();
});

test("a click reports the target, not a destination", { skip }, () => {
  // Leaf never navigates: the host may want a modal, a new tab, or a
  // "create this note" flow for a target that does not exist yet.
  const e = wikiEditor(LINKS, { readonly: true });

  e._onWikiLinkTargets({ targets: { Ideas: { href: "/notes/abc", exists: true } } });
  const payload = clickFirstLink(e, {})[0].payload;

  assert.equal(payload.target, "Ideas");
  assert.equal(payload.href, "/notes/abc");
  e.cleanup();
});
