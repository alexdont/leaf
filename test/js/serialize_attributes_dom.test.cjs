"use strict";

// Image markup is written into the markdown as HTML. Its attribute values
// come from the DOM — a resized picture, a caption, a URL from a dialog —
// and have to be escaped on the way, or a quote in one of them ends the
// attribute and starts another.

const { test } = require("node:test");
const assert = require("node:assert");
const dom = require("./support/dom.cjs");

test("a sized image's attributes are escaped", { skip: dom.skip }, () => {
  const e = dom.editor("<p></p>");
  const img = document.createElement("img");
  img.setAttribute("src", 'x" onerror="alert(1)');
  img.setAttribute("alt", 'a"b');
  img.setAttribute("width", "10");
  e._visualEl.firstChild.appendChild(img);

  const md = e._currentMarkdown();
  assert.ok(md.includes('<img src="x&quot; onerror=&quot;alert(1)" alt="a&quot;b" width="10" />'), md);
  assert.ok(!/onerror="/.test(md), "no attribute of its own");
  e.cleanup();
});

test("a figure's caption and alignment are escaped", { skip: dom.skip }, () => {
  const e = dom.editor("<p></p>");
  const figure = document.createElement("figure");
  figure.setAttribute("data-align", 'left"x');
  const img = document.createElement("img");
  img.setAttribute("src", "/a.png");
  img.setAttribute("alt", "a");
  const cap = document.createElement("figcaption");
  cap.textContent = 'say <b>"hi"</b>';
  figure.appendChild(img);
  figure.appendChild(cap);
  e._visualEl.appendChild(figure);

  const md = e._currentMarkdown();
  assert.ok(md.includes('<figure data-align="left&quot;x">'), md);
  assert.ok(md.includes("<figcaption>say &lt;b&gt;&quot;hi&quot;&lt;/b&gt;</figcaption>"), md);
  e.cleanup();
});
