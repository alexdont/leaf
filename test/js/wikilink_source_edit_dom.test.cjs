"use strict";

// Text typed inside an ACTIVE hybrid wiki link must reach the markdown.
//
// Closing a link with `]]` leaves the caret at the end of the closing marker
// span, so the next characters land INSIDE `.leaf-wikilink`. Both serializers
// used to emit `data-leaf-wikilink-raw` for the span, which is the source as
// it was when the span was built, and silently dropped everything typed into
// it since: `A [[B]] C` was saved as `A [[B]]`.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

const link = (raw, inside) =>
  `<span class="leaf-wikilink leaf-source-active" data-leaf-wikilink="B" ` +
  `data-leaf-wikilink-raw="${raw}">${inside}</span>`;

const marker = (t) => `<span class="leaf-source-marker">${t}</span>`;

function hybrid(html) {
  const e = editor(html, "hybrid");
  e._wikiLinks = true;
  return e;
}

const CASES = [
  {
    name: "text typed after `]]` lands in the closing marker",
    inside: marker("[[") + "B" + marker("]] C"),
    raw: "[[B]]",
    markdown: "A [[B]] C",
  },
  {
    name: "an edited target",
    inside: marker("[[") + "Bee" + marker("]]"),
    raw: "[[B]]",
    markdown: "A [[Bee]]",
  },
  {
    name: "an edited alias",
    inside: marker("[[B|") + "new label" + marker("]]"),
    raw: "[[B|old]]",
    markdown: "A [[B|new label]]",
  },
  {
    name: "an untouched link",
    inside: marker("[[") + "B" + marker("]]"),
    raw: "[[B]]",
    markdown: "A [[B]]",
  },
];

for (const c of CASES) {
  test(`keystroke rebuild keeps it: ${c.name}`, { skip }, () => {
    const e = hybrid(`<p data-leaf-source="p">A ${link(c.raw, c.inside)}</p>`);
    const p = e._visualEl.querySelector("p");

    assert.equal(e._serializeBlockInline(p).source, c.markdown);
    e.cleanup();
  });

  test(`save keeps it: ${c.name}`, { skip }, () => {
    const e = hybrid(`<p data-leaf-source="p">A ${link(c.raw, c.inside)}</p>`);

    assert.equal(e._currentMarkdown().trim(), c.markdown);
    e.cleanup();
  });
}

test("the caret typed after `]]` stays after the text it typed", { skip }, () => {
  const e = hybrid(`<p data-leaf-source="p">A ${link("[[B]]", marker("[[") + "B" + marker("]] C"))}</p>`);
  const p = e._visualEl.querySelector("p");
  const closing = p.querySelectorAll(".leaf-source-marker")[1].firstChild;

  // Caret after "]] C" — the end of the closing marker's text.
  const out = e._serializeBlockInline(p, closing, closing.textContent.length);

  assert.equal(out.source, "A [[B]] C");
  assert.equal(out.cursorOffset, "A [[B]] C".length);
  e.cleanup();
});

test("a rendered (inactive) link without markers still emits its source", { skip }, () => {
  const e = hybrid(
    `<p>see <span class="leaf-wikilink" data-leaf-wikilink="Ideas" ` +
      `data-leaf-wikilink-raw="[[Ideas|my notes]]">my notes</span></p>`
  );

  assert.equal(e._currentMarkdown().trim(), "see [[Ideas|my notes]]");
  e.cleanup();
});
