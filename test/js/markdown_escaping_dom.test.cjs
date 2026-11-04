"use strict";

// Text in a rendered block is content, not syntax. `price *is* 5` typed in
// visual mode used to come back as italic after a reload, and `# todo` at
// the start of a line as a heading. The serializers escape what markdown
// would read as syntax; the hybrid renderer hides the backslashes again.

const test = require("node:test");
const assert = require("node:assert/strict");

const { skip, editor } = require("./support/dom.cjs");

function markdownOf(html, mode = "visual") {
  const e = editor(html, mode);
  const md = e._currentMarkdown();
  e.cleanup();
  return md;
}

test("inline syntax characters in text are escaped", { skip }, () => {
  assert.equal(markdownOf("<p>price *is* 5_000 and snake_case, __init__</p>"), "price \\*is\\* 5_000 and snake_case, \\_\\_init\\_\\_");
  assert.equal(markdownOf("<p>use `x` or ~~no~~</p>"), "use \\`x\\` or \\~\\~no\\~\\~");
  assert.equal(markdownOf("<p>[not a link] and a &lt;b&gt; tag, &amp;amp; too</p>"), "\\[not a link] and a \\<b> tag, \\&amp; too");
  assert.equal(markdownOf("<p>a \\* literal backslash \\ alone</p>"), "a \\\\\\* literal backslash \\ alone");
});

test("what starts a block is escaped at the start of a line", { skip }, () => {
  assert.equal(markdownOf("<p># not a heading</p>"), "\\# not a heading");
  assert.equal(markdownOf("<p>- not a list</p>"), "\\- not a list");
  assert.equal(markdownOf("<p>1. nope</p>"), "1\\. nope");
  assert.equal(markdownOf("<p>&gt; no quote</p>"), "\\> no quote");
  assert.equal(markdownOf("<p>---</p>"), "\\---");
  assert.equal(markdownOf("<p>one<br>- two</p>"), "one\n\\- two");
  assert.equal(markdownOf("<p>#tag mid line # x</p>"), "#tag mid line # x");
});

test("code, chips and a block in source form are left alone", { skip }, () => {
  assert.equal(markdownOf("<p><code>a*b</code></p>"), "`a*b`");
  assert.equal(markdownOf("<pre><code>*x* # y</code></pre>"), "```\n*x* # y\n```");
  assert.equal(markdownOf('<p data-leaf-source="p">*raw* source</p>', "hybrid"), "*raw* source");
  assert.equal(
    markdownOf('<p><span class="leaf-atomic" data-leaf-raw="&lt;Hero a=&quot;*&quot;/&gt;">Hero</span></p>'),
    '<Hero a="*"/>'
  );
});

test("a code span holding a backtick is fenced by more of them", { skip }, () => {
  assert.equal(markdownOf("<p><code>a`b</code></p>"), "``a`b``");
  assert.equal(markdownOf("<p><code>`tick</code></p>"), "`` `tick ``");
});

test("link text and destinations survive brackets and parentheses", { skip }, () => {
  assert.equal(markdownOf('<p><a href="/x">a]b</a></p>'), "[a\\]b](/x)");
  assert.equal(markdownOf('<p><a href="https://x.y/a(b)">t</a></p>'), "[t](<https://x.y/a(b)>)");
  assert.equal(markdownOf('<p><img src="/a b.png" alt="x]y"></p>'), "![x\\]y](</a b.png>)");
});

test("underline, mark and kbd are written as the tags they are", { skip }, () => {
  assert.equal(markdownOf("<p><u>u</u> <mark>m</mark> <kbd>k</kbd></p>"), "<u>u</u> <mark>m</mark> <kbd>k</kbd>");
});

test("a line break inside a table cell does not break the table", { skip }, () => {
  const md = markdownOf("<table><tr><th>h</th></tr><tr><td>l1<br>l2</td></tr></table>");
  assert.ok(md.includes("| l1<br>l2 |"), md);
  assert.equal(md.split("\n").length, 3);
});

test("a second paragraph in a list item stays in the item", { skip }, () => {
  assert.equal(markdownOf("<ul><li><p>one</p><p>two</p></li><li>three</li></ul>"), "- one\n\n  two\n- three");
});

test("the hybrid renderer shows an escaped character without its backslash", { skip }, () => {
  const e = editor("<p>x</p>", "hybrid");
  const block = e._renderBlockFromSource("\\*x\\* and *y*, \\# not a heading");

  assert.equal(block.tagName, "P");
  assert.equal(block.textContent, "*x* and y, # not a heading");
  assert.equal(block.querySelectorAll("em").length, 1);
  assert.equal(block.querySelector("em").textContent, "y");
  e.cleanup();
});

test("an escaped marker does not make a heading or a rule", { skip }, () => {
  const e = editor("<p>x</p>", "hybrid");
  assert.equal(e._renderBlockFromSource("\\# x").tagName, "P");
  assert.equal(e._renderBlockFromSource("\\---").tagName, "P");
  assert.equal(e._renderBlockFromSource("# x").tagName, "H1");
  e.cleanup();
});

test("serializing a rendered block escapes, and re-rendering it gives the text back", { skip }, () => {
  const e = editor("<p>x</p>", "hybrid");
  const proto = Object.getPrototypeOf(e);
  const block = e._renderBlockFromSource("\\*x\\* and *y*");
  e._visualEl.appendChild(block);

  const source = proto._serializeBlockInline.call(e, block).source;
  assert.equal(source, "\\*x\\* and *y*");

  const again = e._renderBlockFromSource(source);
  assert.equal(again.textContent, "*x* and y");
  e.cleanup();
});

test("the inline scanner never matches across an escape", { skip }, () => {
  const e = editor("<p>x</p>", "hybrid");
  const matches = e._scanInlineMatches("\\*x\\* and *y* [a\\]b](/u\\))");

  assert.equal(matches.length, 2);
  assert.equal(matches[0].start, 10);
  assert.equal(matches[0].body, "y");
  assert.equal(matches[1].body, "a\\]b");
  assert.equal(matches[1].href, "/u)");
  e.cleanup();
});

test("in source form the backslash is a marker, so the shared text is the character", { skip }, () => {
  const e = editor("<p>x</p>", "hybrid");
  const host = document.createElement("p");
  host.setAttribute("data-leaf-source", "p");
  e._visualEl.appendChild(host);
  const source = "\\*x\\* y";
  const scan = e._scanSource(source);
  const caret = e._buildSourceFragment(host, source, scan, 2);

  const markers = host.querySelectorAll(".leaf-source-marker.leaf-escape-marker");
  assert.equal(markers.length, 2);
  assert.equal(host.textContent, source, "the source is all there");
  assert.equal(host.querySelectorAll("em").length, 0);
  assert.equal(e._visibleText(host), "*x* y", "what the sessions share has no backslashes");
  assert.ok(caret && caret.node, "the caret lands somewhere in the text");
  e.cleanup();
});
