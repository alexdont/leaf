/**
 * Leaf — Dual Mode Content Editor (Visual + Markdown)
 *
 * Standalone vanilla JS. No build step, no npm dependencies.
 * Visual mode uses contenteditable + execCommand.
 * Markdown mode uses a plain textarea with toolbar support.
 * Content syncs between modes via server-side conversion (Earmark) and
 * client-side HTML→Markdown conversion.
 *
 * SETUP: Add the hook to your app.js:
 *
 *   import "../../../deps/leaf/priv/static/assets/leaf.js"
 *
 *   let Hooks = {
 *     Leaf: window.LeafHooks.Leaf,
 *     // ... your other hooks
 *   }
 */
(function () {
  "use strict";

  if (window.LeafEditorLoaded) return;
  window.LeafEditorLoaded = true;

  window.LeafHooks = window.LeafHooks || {};

  // =========================================================================
  // Inject CSS styles for the visual editor
  // =========================================================================

  var EDITOR_CSS = [
    // Placeholder
    ".content-editor-visual:empty::before {",
    "  content: attr(data-placeholder);",
    "  color: color-mix(in oklab, var(--color-base-content, #1f2937) 35%, transparent);",
    "  pointer-events: none;",
    "  position: absolute;",
    "}",
    ".content-editor-visual { position: relative; -webkit-user-select: text; user-select: text; }",

    // Typography
    ".content-editor-visual h1 { font-size: 2em; font-weight: 700; margin: 0.67em 0; line-height: 1.2; }",
    ".content-editor-visual h2 { font-size: 1.5em; font-weight: 600; margin: 0.6em 0; line-height: 1.3; }",
    ".content-editor-visual h3 { font-size: 1.25em; font-weight: 600; margin: 0.5em 0; line-height: 1.4; }",
    ".content-editor-visual h4 { font-size: 1.1em; font-weight: 600; margin: 0.4em 0; line-height: 1.4; }",
    ".content-editor-visual p { margin: 0.5em 0; }",
    ".content-editor-visual p:first-child, .content-editor-visual h1:first-child,",
    "  .content-editor-visual h2:first-child, .content-editor-visual h3:first-child { margin-top: 0; }",

    // Inline
    ".content-editor-visual strong, .content-editor-visual b { font-weight: 700; }",
    ".content-editor-visual em, .content-editor-visual i { font-style: italic; }",
    ".content-editor-visual s, .content-editor-visual del, .content-editor-visual strike { text-decoration: line-through; }",
    ".content-editor-visual u { text-decoration: underline; }",
    ".content-editor-visual code {",
    "  background: var(--color-base-200, #e5e7eb); border-radius: 0.25rem;",
    "  padding: 0.1em 0.35em; font-family: monospace; font-size: 0.9em;",
    "}",

    // Code blocks
    ".content-editor-visual pre {",
    "  background: var(--color-base-200, #e5e7eb); border-radius: 0.5rem;",
    "  padding: 0.75rem 1rem; margin: 0.75em 0; overflow-x: auto;",
    "  font-family: monospace; font-size: 0.875rem; line-height: 1.6;",
    "}",
    ".content-editor-visual pre code { background: none; padding: 0; border-radius: 0; font-size: inherit; }",

    // Blockquote
    ".content-editor-visual blockquote {",
    "  border-left: 3px solid color-mix(in oklab, var(--color-base-content, #1f2937) 25%, transparent);",
    "  padding-left: 1rem; margin: 0.75em 0;",
    "  color: color-mix(in oklab, var(--color-base-content, #1f2937) 70%, transparent);",
    "}",

    // Lists
    ".content-editor-visual ul { list-style-type: disc; padding-left: 1.5rem; margin: 0.5em 0; }",
    ".content-editor-visual ol { list-style-type: decimal; padding-left: 1.5rem; margin: 0.5em 0; }",
    ".content-editor-visual li { margin: 0.2em 0; }",
    ".content-editor-visual li > p { margin: 0; }",

    // Tables
    ".content-editor-visual table { border-collapse: collapse; table-layout: fixed; width: 100%; margin: 0.75em 0; }",
    ".content-editor-visual th, .content-editor-visual td {",
    "  border: 1px solid color-mix(in oklab, var(--color-base-content, #1f2937) 20%, transparent);",
    "  padding: 0.4rem 0.75rem; text-align: left;",
    "  overflow-wrap: anywhere;",
    "}",
    ".content-editor-visual th {",
    "  font-weight: 600;",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 5%, transparent);",
    "}",

    // Links
    ".content-editor-visual a { color: var(--color-primary, #3b82f6); text-decoration: underline; cursor: text; }",
    ".content-editor-visual a:hover { opacity: 0.8; }",

    // Images
    ".content-editor-visual img {",
    "  max-width: 100%; height: auto; border-radius: 0.5rem; margin: 0.75em 0;",
    "  cursor: pointer;",
    "}",
    ".content-editor-visual img.leaf-img-selected {",
    "  outline: 2px solid var(--color-primary, #3b82f6);",
    "  outline-offset: 2px;",
    "}",

    // Image resize handles
    ".leaf-resize-handle {",
    "  position: absolute; width: 10px; height: 10px;",
    "  background: var(--color-base-100, #fff);",
    "  border: 2px solid var(--color-primary, #3b82f6);",
    "  border-radius: 2px; z-index: 51;",
    "}",
    ".leaf-resize-handle--nw { cursor: nw-resize; }",
    ".leaf-resize-handle--ne { cursor: ne-resize; }",
    ".leaf-resize-handle--sw { cursor: sw-resize; }",
    ".leaf-resize-handle--se { cursor: se-resize; }",

    // Drag-and-drop indicator
    ".leaf-drop-indicator {",
    "  position: absolute; left: 0; right: 0; height: 3px;",
    "  background: var(--color-primary, #3b82f6);",
    "  border-radius: 2px; pointer-events: none; z-index: 50;",
    "  transition: top 0.05s ease-out;",
    "}",
    ".leaf-dragging {",
    "  opacity: 0.35 !important;",
    "  outline: 2px dashed var(--color-primary, #3b82f6) !important;",
    "  outline-offset: 2px;",
    "}",

    // Block drag handle
    ".leaf-drag-handle {",
    "  position: absolute; z-index: 52;",
    "  display: flex; align-items: center; justify-content: center;",
    "  width: 28px; height: 28px;",
    "  cursor: grab; border-radius: 6px;",
    "  color: color-mix(in oklab, var(--color-base-content, #1f2937) 30%, transparent);",
    "  background: transparent;",
    "  transition: color 0.1s, background 0.1s;",
    "  user-select: none; -webkit-user-select: none;",
    "}",
    ".leaf-drag-handle:hover {",
    "  color: color-mix(in oklab, var(--color-base-content, #1f2937) 60%, transparent);",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 8%, transparent);",
    "}",
    ".leaf-drag-handle:active { cursor: grabbing; }",
    ".leaf-drag-handle svg { width: 18px; height: 18px; pointer-events: none; }",

    // Horizontal rule
    ".content-editor-visual hr {",
    "  border: none;",
    "  border-top: 1px solid color-mix(in oklab, var(--color-base-content, #1f2937) 15%, transparent);",
    "  margin: 1.5em 0;",
    "}",

    // Selection
    ".content-editor-visual ::selection { background-color: Highlight !important; color: HighlightText !important; }",
    ".content-editor-visual *::selection { background-color: Highlight !important; color: HighlightText !important; }",

    // Link popover — floating island
    ".leaf-link-popover {",
    "  position: absolute; z-index: 50;",
    "  display: flex; align-items: center; gap: 0.5rem;",
    "  background: var(--color-base-200, #e5e7eb); color: var(--color-base-content, #1f2937);",
    "  border: 1px solid var(--color-base-300, #d1d5db);",
    "  border-radius: 9999px; padding: 0.4rem 0.5rem 0.4rem 0.75rem;",
    "  box-shadow: 0 4px 16px rgba(0,0,0,0.12), 0 1px 4px rgba(0,0,0,0.08);",
    "  font-size: 0.8125rem; line-height: 1;",
    "  animation: leaf-popover-in 0.15s ease-out;",
    "  white-space: nowrap;",
    "}",
    "@keyframes leaf-popover-in { from { opacity: 0; transform: translateY(6px) scale(0.97); } to { opacity: 1; transform: translateY(0) scale(1); } }",
    ".leaf-link-popover a {",
    "  color: var(--color-primary, #3b82f6); text-decoration: none; max-width: 220px;",
    "  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; cursor: pointer;",
    "}",
    ".leaf-link-popover a:hover { text-decoration: underline; }",
    ".leaf-link-popover .leaf-popover-actions {",
    "  display: flex; align-items: center; gap: 0.125rem;",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 8%, transparent);",
    "  border-radius: 9999px; padding: 0.125rem;",
    "}",
    ".leaf-link-popover button {",
    "  background: none; border: none; cursor: pointer; padding: 0.3rem;",
    "  border-radius: 9999px; color: color-mix(in oklab, var(--color-base-content, #1f2937) 50%, transparent);",
    "  display: flex; align-items: center;",
    "  transition: background 0.1s, color 0.1s;",
    "}",
    ".leaf-link-popover button:hover {",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 12%, transparent);",
    "  color: var(--color-base-content, #1f2937);",
    "}",
    ".leaf-link-popover .leaf-popover-divider {",
    "  width: 1px; height: 0.875rem;",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 15%, transparent);",
    "}",

    // Image URL dialog
    ".leaf-image-url-backdrop {",
    "  position: fixed; inset: 0; z-index: 99999;",
    "  background: rgba(0,0,0,0.15);",
    "}",
    ".leaf-image-url-dialog {",
    "  position: fixed; z-index: 100000;",
    "  background: var(--color-base-200, #e5e7eb); color: var(--color-base-content, #1f2937);",
    "  border: 1px solid var(--color-base-300, #d1d5db);",
    "  border-radius: 0.5rem; padding: 0.75rem;",
    "  box-shadow: 0 4px 16px rgba(0,0,0,0.12), 0 1px 4px rgba(0,0,0,0.08);",
    "  font-size: 0.8125rem; line-height: 1;",
    "  animation: leaf-popover-in 0.15s ease-out;",
    "  display: flex; flex-direction: column; gap: 0.5rem;",
    "  width: 300px;",
    "}",
    ".leaf-image-url-dialog input {",
    "  width: 100%; padding: 0.375rem 0.5rem; font-size: 0.8125rem;",
    "  border: 1px solid var(--color-base-300, #d1d5db); border-radius: 0.375rem;",
    "  background: var(--color-base-100, #fff); color: var(--color-base-content, #1f2937);",
    "  outline: none;",
    "}",
    ".leaf-image-url-dialog input:focus {",
    "  border-color: var(--color-primary, #3b82f6);",
    "  box-shadow: 0 0 0 1px var(--color-primary, #3b82f6);",
    "}",
    ".leaf-image-url-dialog label {",
    "  font-size: 0.75rem; font-weight: 500;",
    "  color: color-mix(in oklab, var(--color-base-content, #1f2937) 70%, transparent);",
    "}",
    ".leaf-image-url-dialog .leaf-image-url-actions {",
    "  display: flex; justify-content: flex-end; gap: 0.375rem; margin-top: 0.25rem;",
    "}",
    ".leaf-image-url-dialog .leaf-image-url-actions button {",
    "  padding: 0.375rem 0.75rem; font-size: 0.75rem; font-weight: 500;",
    "  border-radius: 0.375rem; border: none; cursor: pointer;",
    "  transition: background 0.1s, color 0.1s;",
    "}",
    ".leaf-image-url-dialog .leaf-image-url-cancel {",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 10%, transparent);",
    "  color: var(--color-base-content, #1f2937);",
    "}",
    ".leaf-image-url-dialog .leaf-image-url-cancel:hover {",
    "  background: color-mix(in oklab, var(--color-base-content, #1f2937) 18%, transparent);",
    "}",
    ".leaf-image-url-dialog .leaf-image-url-insert {",
    "  background: var(--color-primary, #3b82f6); color: #fff;",
    "}",
    ".leaf-image-url-dialog .leaf-image-url-insert:hover { opacity: 0.9; }",

    // Sticky toolbar
    "[data-visual-toolbar].leaf-toolbar-sticky {",
    "  position: fixed;",
    "  z-index: 10000;",
    "  box-sizing: border-box;",
    "}",
    ".leaf-toolbar-placeholder { visibility: hidden; }",

    // Resize-grip tooltip (shown when the mouse is over the bottom-right
    // resize grip; hint that double-click auto-fits height to content).
    ".leaf-grip-tooltip {",
    "  position: fixed; pointer-events: none; z-index: 100000;",
    "  background: rgba(17, 24, 39, 0.92); color: #f9fafb;",
    "  padding: 4px 8px; border-radius: 4px;",
    "  font: 500 11px/1.3 ui-sans-serif, system-ui, -apple-system, sans-serif;",
    "  white-space: nowrap;",
    "  opacity: 0; transform: translateY(2px);",
    "  transition: opacity 0.12s ease-out, transform 0.12s ease-out;",
    "  box-shadow: 0 2px 8px rgba(0,0,0,0.18);",
    "}",
    ".leaf-grip-tooltip.leaf-grip-tooltip-visible {",
    "  opacity: 1; transform: translateY(0);",
    "}",
  ].join("\n");

  function injectStyles() {
    if (document.getElementById("leaf-content-editor-css")) return;
    var style = document.createElement("style");
    style.id = "leaf-content-editor-css";
    style.textContent = EDITOR_CSS;
    document.head.appendChild(style);
  }

  // =========================================================================
  // HTML → Markdown converter (pure DOM walking)
  // =========================================================================

  function htmlToMarkdown(html) {
    var container = document.createElement("div");
    container.innerHTML = html;
    return nodeToMarkdown(container).replace(/\n{3,}/g, "\n\n").trim();
  }

  function nodeToMarkdown(node) {
    var result = "";
    var prevWasBr = false;
    for (var i = 0; i < node.childNodes.length; i++) {
      var child = node.childNodes[i];
      var emit = convertNode(child);

      // Earmark's HTML output (with breaks: true) puts a literal "\n" after
      // every <br> as pretty-print whitespace. Without stripping, the
      // <br>'s "\n" plus the text node's leading "\n" become "\n\n" — a
      // markdown paragraph break — and the round-trip splits a single
      // paragraph into multiple.
      if (prevWasBr && child.nodeType === Node.TEXT_NODE) {
        emit = emit.replace(/^[\n\r\t]+/, "");
      }

      prevWasBr =
        child.nodeType === Node.ELEMENT_NODE &&
        child.tagName &&
        child.tagName.toLowerCase() === "br";

      result += emit;
    }
    return result;
  }

  // Move leading/trailing whitespace outside markers so markdown stays valid
  // e.g. <i>works </i> → "*works* " instead of "*works *"
  function wrapInline(text, marker) {
    if (!text) return marker + marker;
    var leading = text.match(/^(\s*)/)[0];
    var trailing = text.match(/(\s*)$/)[0];
    var trimmed = text.substring(leading.length, text.length - trailing.length);
    if (!trimmed) return leading + trailing;
    return leading + marker + trimmed + marker + trailing;
  }

  function convertNode(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return node.textContent;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) {
      return "";
    }

    var tag = node.tagName.toLowerCase();
    var inner = nodeToMarkdown(node);

    switch (tag) {
      case "h1":
        return "\n# " + inner.trim() + "\n\n";
      case "h2":
        return "\n## " + inner.trim() + "\n\n";
      case "h3":
        return "\n### " + inner.trim() + "\n\n";
      case "h4":
        return "\n#### " + inner.trim() + "\n\n";
      case "h5":
        return "\n##### " + inner.trim() + "\n\n";
      case "h6":
        return "\n###### " + inner.trim() + "\n\n";

      case "p":
        return inner.trim() + "\n\n";

      case "br":
        // The Shift+Enter handler appends a filler <br> at the end of a
        // block so the cursor has a visible empty line to sit on. That
        // filler is for visual presentation only — emitting "\n" for it
        // would cause "<br><br>" sequences to round-trip as paragraph
        // breaks, splitting a single paragraph into multiple.
        if (node.hasAttribute && node.hasAttribute("data-leaf-filler")) {
          return "";
        }
        return "\n";

      case "strong":
      case "b":
        return wrapInline(inner, "**");

      case "em":
      case "i":
        return wrapInline(inner, "*");

      case "s":
      case "del":
      case "strike":
        return wrapInline(inner, "~~");

      case "code":
        if (
          node.parentElement &&
          node.parentElement.tagName.toLowerCase() === "pre"
        ) {
          return inner;
        }
        return "`" + inner + "`";

      case "pre":
        return "\n```\n" + inner.trim() + "\n```\n\n";

      case "a":
        var href = node.getAttribute("href") || "";
        return "[" + inner + "](" + href + ")";

      case "img":
        var src = node.getAttribute("src") || "";
        var alt = node.getAttribute("alt") || "";
        var w = node.getAttribute("width");
        var h = node.getAttribute("height");
        if (w || h) {
          var tag = '<img src="' + src + '" alt="' + alt + '"';
          if (w) tag += ' width="' + w + '"';
          if (h) tag += ' height="' + h + '"';
          tag += ' />';
          return tag;
        }
        return "![" + alt + "](" + src + ")";

      case "blockquote":
        return (
          "\n" +
          inner
            .trim()
            .split("\n")
            .map(function (line) {
              return "> " + line;
            })
            .join("\n") +
          "\n\n"
        );

      case "ul":
        return "\n" + convertList(node, "ul") + "\n";

      case "ol":
        return "\n" + convertList(node, "ol") + "\n";

      case "li":
        return inner;

      case "hr":
        return "\n---\n\n";

      case "table":
        return "\n" + convertTable(node) + "\n";

      case "thead":
      case "tbody":
      case "tr":
      case "th":
      case "td":
        return inner;

      case "div":
        return inner + "\n";

      default:
        return inner;
    }
  }

  function convertList(listNode, type) {
    var items = [];
    var index = 1;
    for (var i = 0; i < listNode.children.length; i++) {
      var child = listNode.children[i];
      if (child.tagName.toLowerCase() === "li") {
        var prefix = type === "ol" ? index + ". " : "- ";
        var content = nodeToMarkdown(child).trim();
        items.push(prefix + content);
        index++;
      }
    }
    return items.join("\n");
  }

  function convertTable(tableNode) {
    var rows = tableNode.querySelectorAll("tr");
    if (!rows.length) return "";
    var lines = [];
    for (var i = 0; i < rows.length; i++) {
      var cells = rows[i].querySelectorAll("th, td");
      var parts = [];
      for (var j = 0; j < cells.length; j++) {
        parts.push(nodeToMarkdown(cells[j]).trim().replace(/\|/g, "\\|"));
      }
      lines.push("| " + parts.join(" | ") + " |");
      // Add separator after header row
      if (i === 0) {
        var sep = [];
        for (var k = 0; k < parts.length; k++) sep.push("---");
        lines.push("| " + sep.join(" | ") + " |");
      }
    }
    return lines.join("\n") + "\n";
  }

  // =========================================================================
  // Clean paste — strips Word/Google Docs junk, keeps structure
  // =========================================================================

  function cleanPastedHtml(html) {
    var container = document.createElement("div");
    container.innerHTML = html;

    container.querySelectorAll("[style]").forEach(function (el) {
      el.removeAttribute("style");
    });

    container.querySelectorAll("[class]").forEach(function (el) {
      el.removeAttribute("class");
    });

    container.querySelectorAll("span").forEach(function (span) {
      var parent = span.parentNode;
      while (span.firstChild) {
        parent.insertBefore(span.firstChild, span);
      }
      parent.removeChild(span);
    });

    container
      .querySelectorAll("meta, style, link, script, title, xml")
      .forEach(function (el) {
        el.remove();
      });

    container.querySelectorAll("[id]").forEach(function (el) {
      el.removeAttribute("id");
    });

    return container.innerHTML;
  }

  // =========================================================================
  // Markdown textarea helpers
  // =========================================================================

  function markdownFormat(textarea, before, after, pushFn) {
    var start = textarea.selectionStart;
    var end = textarea.selectionEnd;
    var text = textarea.value;
    var selected = text.substring(start, end);

    textarea.value =
      text.substring(0, start) + before + selected + after + text.substring(end);
    textarea.selectionStart = start + before.length;
    textarea.selectionEnd = end + before.length;
    textarea.focus();
    if (pushFn) pushFn(textarea.value);
  }

  function markdownLinePrefix(textarea, prefix, pushFn) {
    var start = textarea.selectionStart;
    var text = textarea.value;

    // Find start of current line
    var lineStart = text.lastIndexOf("\n", start - 1) + 1;
    var lineEnd = text.indexOf("\n", start);
    if (lineEnd === -1) lineEnd = text.length;

    var line = text.substring(lineStart, lineEnd);

    // Toggle: if line already starts with prefix, remove it
    if (line.startsWith(prefix)) {
      textarea.value =
        text.substring(0, lineStart) +
        line.substring(prefix.length) +
        text.substring(lineEnd);
      textarea.selectionStart = start - prefix.length;
      textarea.selectionEnd = start - prefix.length;
    } else {
      // Remove existing heading prefixes before adding new one
      var cleaned = line.replace(/^#{1,6}\s|^[-*+]\s|^\d+\.\s|^>\s/, "");
      textarea.value =
        text.substring(0, lineStart) + prefix + cleaned + text.substring(lineEnd);
      var offset = prefix.length + cleaned.length - line.length;
      textarea.selectionStart = start + offset;
      textarea.selectionEnd = start + offset;
    }

    textarea.focus();
    if (pushFn) pushFn(textarea.value);
  }

  function markdownIndent(textarea, direction, pushFn) {
    var start = textarea.selectionStart;
    var end = textarea.selectionEnd;
    var text = textarea.value;

    // Find all lines in selection (or current line if no selection)
    var lineStart = text.lastIndexOf("\n", start - 1) + 1;
    var lineEnd = text.indexOf("\n", end);
    if (lineEnd === -1) lineEnd = text.length;

    var block = text.substring(lineStart, lineEnd);
    var lines = block.split("\n");
    var indent = "  ";
    var delta = 0;
    var firstDelta = 0;

    var result = lines.map(function (line, i) {
      if (direction === "indent") {
        if (i === 0) firstDelta = indent.length;
        delta += indent.length;
        return indent + line;
      } else {
        if (line.startsWith(indent)) {
          if (i === 0) firstDelta = -indent.length;
          delta -= indent.length;
          return line.substring(indent.length);
        } else if (line.startsWith(" ")) {
          if (i === 0) firstDelta = -1;
          delta -= 1;
          return line.substring(1);
        }
        return line;
      }
    });

    textarea.value = text.substring(0, lineStart) + result.join("\n") + text.substring(lineEnd);
    textarea.selectionStart = Math.max(lineStart, start + firstDelta);
    textarea.selectionEnd = end + delta;
    textarea.focus();
    if (pushFn) pushFn(textarea.value);
  }

  function markdownLink(textarea, pushFn) {
    var start = textarea.selectionStart;
    var end = textarea.selectionEnd;
    var text = textarea.value;
    var selected = text.substring(start, end);

    var url = prompt("Enter URL:", "https://");
    if (url === null) return;

    var linkText = selected || "link text";
    var md = "[" + linkText + "](" + url + ")";

    textarea.value = text.substring(0, start) + md + text.substring(end);
    textarea.selectionStart = start + 1;
    textarea.selectionEnd = start + 1 + linkText.length;
    textarea.focus();
    if (pushFn) pushFn(textarea.value);
  }

  function markdownInsert(textarea, snippet, pushFn) {
    var start = textarea.selectionStart;
    var text = textarea.value;

    textarea.value = text.substring(0, start) + snippet + text.substring(start);
    textarea.selectionStart = start + snippet.length;
    textarea.selectionEnd = start + snippet.length;
    textarea.focus();
    if (pushFn) pushFn(textarea.value);
  }

  // =========================================================================
  // LiveView Hook
  // =========================================================================

  window.LeafHooks.Leaf = {
    mounted() {
      injectStyles();
      this.el.dataset.leafMountState = "ready";

      this._editorId = this.el.dataset.editorId;
      this._mode = this.el.dataset.mode || "visual";
      this._debounceMs = parseInt(this.el.dataset.debounce || "400", 10);
      this._readonly = this.el.dataset.readonly === "true";
      this._hasUpload = this.el.dataset.hasUpload === "true";
      this._debounceTimer = null;
      this._markdownDebounceTimer = null;
      this._htmlDebounceTimer = null;

      this._visualEl = this.el.querySelector("[data-editor-visual]");
      this._visualWrapper = this.el.querySelector("[data-visual-wrapper]");
      this._markdownWrapper = this.el.querySelector(
        "[data-markdown-wrapper]"
      );
      this._htmlWrapper = this.el.querySelector("[data-html-wrapper]");

      if (this._visualEl) {
        document.execCommand("defaultParagraphSeparator", false, "p");

        this._visualEl.addEventListener(
          "input",
          this._onVisualInput.bind(this)
        );

        this._visualEl.addEventListener(
          "keydown",
          this._onVisualKeydown.bind(this)
        );

        this._visualEl.addEventListener("paste", this._onPaste.bind(this));

        if (
          this._visualEl.innerHTML.trim() === "" ||
          this._visualEl.innerHTML === "<br>"
        ) {
          this._visualEl.innerHTML = "<p><br></p>";
        }
      }

      this._setupToolbar();
      this._setupStickyToolbar();
      this._setupModeSwitcher();
      this._setupLinkPopover();
      this._setupImageDragAndDrop();
      this._registerMarkdownHelpers();
      this._setupMarkdownTextarea();
      this._setupHtmlTextarea();
      this._setupGripDoubleClick();

      this._wordCountEl = this.el.querySelector("[data-word-count]");
      this._charCountEl = this.el.querySelector("[data-char-count]");
      this._updateCounts();

      // Handle commands from LiveView
      this.handleEvent(
        "leaf-command:" + this._editorId,
        this._handleCommand.bind(this)
      );

      // Handle HTML content pushed from server (markdown→visual sync)
      this.handleEvent(
        "leaf-set-html:" + this._editorId,
        function (payload) {
          if (this._visualEl && payload.html !== undefined) {
            this._visualEl.innerHTML = payload.html || "<p><br></p>";
            // DOM was replaced — old block references are stale
            this._dragHandleBlock = null;
          }
        }.bind(this)
      );

      // Handle HTML pushed to the HTML textarea (markdown→html conversion)
      this.handleEvent(
        "leaf-set-html-textarea:" + this._editorId,
        function (payload) {
          var ta = this._getHtmlTextarea();
          if (ta && payload.html !== undefined) {
            ta.value = payload.html;
          }
        }.bind(this)
      );
    },

    updated() {
      // Server always renders data-leaf-mount-state="loading"; once the hook
      // is mounted we own the state, so keep it pinned to "ready" through
      // any parent-triggered re-render.
      this.el.dataset.leafMountState = "ready";

      if (!this._visualEl) return;
      var newReadonly = this.el.dataset.readonly === "true";
      if (newReadonly !== this._readonly) {
        this._readonly = newReadonly;
        this._visualEl.contentEditable = !newReadonly;
      }
      var newHasUpload = this.el.dataset.hasUpload === "true";
      if (newHasUpload !== this._hasUpload) {
        this._hasUpload = newHasUpload;
      }

      // Re-find drag handle after morphdom patch (element may have been replaced)
      if (this._visualWrapper) {
        var newHandle = this._visualWrapper.querySelector("[data-drag-handle]");
        if (newHandle && newHandle !== this._dragHandle) {
          this._dragHandle = newHandle;
          this._dragHandleBlock = null;
        }
      }

      // Re-show image popover if it was active but removed by morphdom
      if (this._imagePopoverTarget && this._imagePopoverEl && !this._imagePopoverEl.parentNode) {
        var imgTarget = this._imagePopoverTarget;
        this._imagePopoverEl = null;
        this._resizeHandles = null;
        this._showImagePopover(imgTarget);
      }

      // Re-insert sticky placeholder if morphdom removed it
      if (
        this._stickyPlaceholder &&
        !this._stickyPlaceholder.parentNode &&
        this._stickyToolbarEl
      ) {
        this._stickyToolbarEl.parentNode.insertBefore(
          this._stickyPlaceholder,
          this._stickyToolbarEl
        );
      }
    },

    destroyed() {
      if (this._debounceTimer) {
        clearTimeout(this._debounceTimer);
      }
      if (this._markdownDebounceTimer) {
        clearTimeout(this._markdownDebounceTimer);
      }
      if (this._htmlDebounceTimer) {
        clearTimeout(this._htmlDebounceTimer);
      }

      this._cleanupDrag();
      if (this._imgObserver) {
        this._imgObserver.disconnect();
        this._imgObserver = null;
      }

      this._cleanupStickyToolbar();
      this._closeEmojiPicker();
      this._dismissLinkPopover();
      this._dismissImageUrlDialog();
      if (this._gripTooltipCleanup) {
        this._gripTooltipCleanup();
        this._gripTooltipCleanup = null;
      }
      if (this._imageDropdownMenu) {
        this._imageDropdownMenu.remove();
        this._imageDropdownMenu = null;
      }
      if (this._imageDropdownBackdrop) {
        this._imageDropdownBackdrop.remove();
        this._imageDropdownBackdrop = null;
      }
      if (this._onDocClickForPopover) {
        document.removeEventListener("mousedown", this._onDocClickForPopover);
      }

      // Clean up global markdown helper functions
      var gid = this._editorId.replace(/-/g, "_") + "_markdown";
      delete window["markdownFormat_" + gid];
      delete window["markdownLinePrefix_" + gid];
      delete window["markdownLink_" + gid];
      delete window["markdownEditorInsert_" + gid];
      delete window["markdownIndent_" + gid];
    },

    // -- Markdown textarea setup --

    _registerMarkdownHelpers: function () {
      var self = this;
      var gid = this._editorId.replace(/-/g, "_") + "_markdown";

      var pushFn = function (value) {
        self._debouncedPushMarkdownChange(value);
      };

      window["markdownFormat_" + gid] = function (before, after) {
        var ta = self._getMarkdownTextarea();
        if (ta) markdownFormat(ta, before, after, pushFn);
      };

      window["markdownLinePrefix_" + gid] = function (prefix) {
        var ta = self._getMarkdownTextarea();
        if (ta) markdownLinePrefix(ta, prefix, pushFn);
      };

      window["markdownLink_" + gid] = function () {
        var ta = self._getMarkdownTextarea();
        if (ta) markdownLink(ta, pushFn);
      };

      window["markdownEditorInsert_" + gid] = function (snippet) {
        var ta = self._getMarkdownTextarea();
        if (ta) markdownInsert(ta, snippet, pushFn);
      };

      window["markdownIndent_" + gid] = function (direction) {
        var ta = self._getMarkdownTextarea();
        if (ta) markdownIndent(ta, direction, pushFn);
      };
    },

    _setupMarkdownTextarea: function () {
      var self = this;
      var textarea = this._getMarkdownTextarea();
      if (!textarea) return;

      this._markdownInputHandler = function () {
        self._debouncedPushMarkdownChange(textarea.value);
        self._updateCounts();
      };

      textarea.addEventListener("input", this._markdownInputHandler);
    },

    _debouncedPushMarkdownChange: function (content) {
      if (this._markdownDebounceTimer)
        clearTimeout(this._markdownDebounceTimer);
      var self = this;
      this._markdownDebounceTimer = setTimeout(function () {
        self.pushEventTo(self.el, "markdown_content_changed", {
          editor_id: self._editorId,
          content: content,
        });
      }, this._debounceMs);
    },

    // -- HTML textarea setup --

    _setupHtmlTextarea: function () {
      var self = this;
      var textarea = this._getHtmlTextarea();
      if (!textarea) return;

      textarea.addEventListener("input", function () {
        self._debouncedPushHtmlChange(textarea.value);
        self._updateCounts();
      });
    },

    _getHtmlTextarea: function () {
      return document.getElementById(
        this._editorId + "-html-textarea"
      );
    },

    _setupGripDoubleClick: function () {
      // Double-clicking the resize grip on any of the three editors should
      // auto-fit that editor's height to its content. The native grip is UA
      // chrome and doesn't fire its own events, but the underlying element
      // still gets dblclick — we just check that the click landed in the
      // bottom-right corner where the grip lives. While we're here, also
      // show a small tooltip when hovering the grip area so the gesture is
      // discoverable.
      var self = this;
      var minHeight = parseInt(this.el.dataset.height || "480", 10);
      var GRIP_PX = 18;
      var tooltip = null;

      var ensureTooltip = function () {
        if (tooltip) return tooltip;
        tooltip = document.createElement("div");
        tooltip.className = "leaf-grip-tooltip";
        tooltip.textContent = "Drag to resize · Double-click to fit content";
        document.body.appendChild(tooltip);
        return tooltip;
      };

      var hideTooltip = function () {
        if (tooltip) tooltip.classList.remove("leaf-grip-tooltip-visible");
      };

      var showTooltipFor = function (el) {
        var rect = el.getBoundingClientRect();
        var tt = ensureTooltip();
        tt.classList.add("leaf-grip-tooltip-visible");
        // Position above the grip, right-aligned with the editor's right edge.
        var ttRect = tt.getBoundingClientRect();
        tt.style.left = Math.max(4, rect.right - ttRect.width - 4) + "px";
        tt.style.top = rect.bottom - GRIP_PX - ttRect.height - 6 + "px";
      };

      var fitToContent = function (el) {
        var prev = el.style.height;
        el.style.height = "auto";
        var natural = el.scrollHeight;
        if (!natural) {
          el.style.height = prev;
          return;
        }
        el.style.height = Math.max(minHeight, natural) + "px";
      };

      var attach = function (el) {
        if (!el) return;
        el.addEventListener("dblclick", function (e) {
          var rect = el.getBoundingClientRect();
          var inGripArea =
            e.clientX > rect.right - GRIP_PX &&
            e.clientY > rect.bottom - GRIP_PX;
          if (!inGripArea) return;
          e.preventDefault();
          fitToContent(el);
        });
        el.addEventListener("mousemove", function (e) {
          var rect = el.getBoundingClientRect();
          var inGripArea =
            e.clientX > rect.right - GRIP_PX &&
            e.clientY > rect.bottom - GRIP_PX;
          if (inGripArea) {
            showTooltipFor(el);
          } else {
            hideTooltip();
          }
        });
        el.addEventListener("mouseleave", hideTooltip);
      };

      attach(this._visualEl);
      attach(this._getMarkdownTextarea());
      attach(this._getHtmlTextarea());

      // Stash for cleanup in destroyed().
      this._gripTooltipCleanup = function () {
        if (tooltip && tooltip.parentNode) {
          tooltip.parentNode.removeChild(tooltip);
        }
        tooltip = null;
      };
    },

    _debouncedPushHtmlChange: function (content) {
      if (this._htmlDebounceTimer)
        clearTimeout(this._htmlDebounceTimer);
      var self = this;
      this._htmlDebounceTimer = setTimeout(function () {
        self.pushEventTo(self.el, "html_content_changed", {
          editor_id: self._editorId,
          content: content,
        });
      }, this._debounceMs);
    },

    // -- Footer counts --

    _updateCounts: function () {
      if (!this._wordCountEl || !this._charCountEl) return;

      var text = "";
      if (this._mode === "visual") {
        text = this._visualEl ? this._visualEl.innerText : "";
      } else if (this._mode === "markdown") {
        var ta = this._getMarkdownTextarea();
        text = ta ? ta.value : "";
      } else if (this._mode === "html") {
        var ta = this._getHtmlTextarea();
        text = ta ? ta.value : "";
      }

      var trimmed = text.trim();
      var words = trimmed === "" ? 0 : trimmed.split(/\s+/).length;
      var chars = trimmed.length;

      this._wordCountEl.textContent = words + (words === 1 ? " word" : " words");
      this._charCountEl.textContent = chars + (chars === 1 ? " char" : " chars");
    },

    // -- Event handlers --

    _onVisualInput: function () {
      if (this._mode !== "visual") return;
      this._dismissLinkPopover();
      this._debouncedPushVisualChange();
      this._updateCounts();
    },

    _onVisualKeydown: function (e) {
      if (this._readonly) return;

      var mod = e.ctrlKey || e.metaKey;

      if (mod && e.key === "b") {
        e.preventDefault();
        if (this._isInsideHeading()) return;
        document.execCommand("bold", false, null);
        this._updateToolbarState();
        return;
      }
      if (mod && e.key === "i") {
        e.preventDefault();
        document.execCommand("italic", false, null);
        this._updateToolbarState();
        return;
      }
      if (mod && e.key === "u") {
        e.preventDefault();
        document.execCommand("underline", false, null);
        return;
      }
      if (mod && e.key === "k") {
        e.preventDefault();
        this._insertLink();
        return;
      }
      if (mod && e.shiftKey && e.key === "x") {
        e.preventDefault();
        document.execCommand("strikeThrough", false, null);
        this._updateToolbarState();
        return;
      }

      if (e.key === "Tab" && !mod) {
        if (
          document.queryCommandState("insertUnorderedList") ||
          document.queryCommandState("insertOrderedList")
        ) {
          e.preventDefault();
          if (e.shiftKey) {
            document.execCommand("outdent", false, null);
          } else {
            document.execCommand("indent", false, null);
          }
          return;
        }
      }

      if (e.key === "Enter" && !e.shiftKey) {
        var block = this._getCurrentBlock();
        if (
          block &&
          block.tagName &&
          block.tagName.toLowerCase() === "blockquote"
        ) {
          var text = block.textContent.trim();
          if (text === "") {
            e.preventDefault();
            document.execCommand("formatBlock", false, "p");
            return;
          }
        }
      }

      if (e.key === "Enter" && e.shiftKey) {
        // Force a soft break inside the current block. Some browsers
        // (notably Chromium with defaultParagraphSeparator set to "p")
        // wrap insertHTML output in a new <p> when the cursor is at the
        // end of a block — manually inserting a <br> via the Range API
        // sidesteps that and guarantees the break stays inside the
        // current parent.
        e.preventDefault();
        var sel = window.getSelection();
        if (!sel || !sel.rangeCount) return;
        var range = sel.getRangeAt(0);
        range.deleteContents();

        // Determine if cursor sits at the end of the current block before
        // we mutate the DOM. Using textContent length (rather than
        // checking br.nextSibling after the insert) avoids false negatives
        // when range.insertNode splits a text node and leaves an empty
        // sibling text node behind.
        var block = this._getCurrentBlock();
        var atEndOfBlock = false;
        if (block) {
          var prefix = document.createRange();
          prefix.selectNodeContents(block);
          prefix.setEnd(range.endContainer, range.endOffset);
          atEndOfBlock = prefix.toString().length === block.textContent.length;
        }

        var br = document.createElement("br");
        range.insertNode(br);

        // At end of a block the inserted <br> alone has no visible height
        // — append a filler <br> so the cursor lands on a visible empty
        // line. This is the standard contenteditable trick. Mark it with
        // data-leaf-filler so htmlToMarkdown emits "" for it and the
        // <br><br> pair doesn't round-trip as a paragraph break.
        if (atEndOfBlock) {
          var filler = document.createElement("br");
          filler.setAttribute("data-leaf-filler", "");
          br.parentNode.insertBefore(filler, br.nextSibling);
        }

        var newRange = document.createRange();
        newRange.setStartAfter(br);
        newRange.collapse(true);
        sel.removeAllRanges();
        sel.addRange(newRange);

        this._visualEl.dispatchEvent(new Event("input", { bubbles: true }));
        return;
      }
    },

    _onPaste: function (e) {
      var clipboardData = e.clipboardData || window.clipboardData;
      if (!clipboardData) return;

      var html = clipboardData.getData("text/html");
      if (html) {
        e.preventDefault();
        var cleaned = cleanPastedHtml(html);
        document.execCommand("insertHTML", false, cleaned);
        return;
      }
    },

    // -- Push content to LiveView --

    _debouncedPushVisualChange: function () {
      if (this._debounceTimer) clearTimeout(this._debounceTimer);
      this._debounceTimer = setTimeout(
        function () {
          if (!this._visualEl) return;
          var html = this._visualEl.innerHTML;
          var markdown = htmlToMarkdown(html);
          this.pushEventTo(this.el, "content_changed", {
            editor_id: this._editorId,
            html: html,
            markdown: markdown,
          });
        }.bind(this),
        this._debounceMs
      );
    },

    // -- Mode switching --

    _setupModeSwitcher: function () {
      var self = this;
      var tabs = this.el.querySelectorAll("[data-mode-tab]");

      tabs.forEach(function (tab) {
        tab.addEventListener("click", function (e) {
          e.preventDefault();
          var newMode = tab.dataset.modeTab;
          if (newMode === self._mode) return;

          self._dismissLinkPopover();

          var oldMode = self._mode;
          self._syncModes(oldMode, newMode);

          self._mode = newMode;
          self._applyModeVisibility(newMode);

          tabs.forEach(function (t) {
            if (t.dataset.modeTab === newMode) {
              t.classList.add("btn-active");
              t.classList.remove("btn-ghost");
            } else {
              t.classList.remove("btn-active");
              t.classList.add("btn-ghost");
            }
          });

          var currentMarkdown = "";
          var ta = self._getMarkdownTextarea();
          if (ta) currentMarkdown = ta.value;
          self.pushEventTo(self.el, "mode_changed", {
            editor_id: self._editorId,
            mode: newMode,
            content: currentMarkdown,
          });

          self._updateCounts();
        });
      });
    },

    _applyModeVisibility: function (mode) {
      var wrappers = [
        { el: this._visualWrapper, mode: "visual" },
        { el: this._markdownWrapper, mode: "markdown" },
        { el: this._htmlWrapper, mode: "html" },
      ];
      wrappers.forEach(function (w) {
        if (!w.el) return;
        if (w.mode === mode) {
          w.el.classList.remove("hidden");
        } else {
          w.el.classList.add("hidden");
        }
      });

      // Hide formatting toolbar in html mode (raw editing)
      var toolbarButtons = this.el.querySelector("[data-visual-toolbar-buttons]");
      if (toolbarButtons) {
        if (mode === "html") {
          toolbarButtons.classList.add("hidden");
          toolbarButtons.classList.remove("contents");
        } else {
          toolbarButtons.classList.remove("hidden");
          toolbarButtons.classList.add("contents");
        }
      }
    },

    _syncModes: function (from, to) {
      var self = this;

      if (from === "visual") {
        // Visual → get innerHTML
        var visualHtml = this._visualEl ? this._visualEl.innerHTML : "";

        if (to === "markdown") {
          var mdTa = this._getMarkdownTextarea();
          if (mdTa) mdTa.value = htmlToMarkdown(visualHtml);
        } else if (to === "html") {
          var htmlTa = this._getHtmlTextarea();
          if (htmlTa) htmlTa.value = visualHtml;
        }

      } else if (from === "markdown") {
        var mdTa = this._getMarkdownTextarea();
        var markdown = mdTa ? mdTa.value : "";

        if (to === "visual") {
          // Server converts markdown→html, pushes back via leaf-set-html event
          this.pushEventTo(this.el, "sync_markdown_to_visual", {
            editor_id: this._editorId,
            markdown: markdown,
          });
        } else if (to === "html") {
          // Server converts markdown→html, pushes to html textarea
          this.pushEventTo(this.el, "convert_markdown_to_html", {
            editor_id: this._editorId,
            markdown: markdown,
          });
        }

      } else if (from === "html") {
        var htmlTa = this._getHtmlTextarea();
        var rawHtml = htmlTa ? htmlTa.value : "";

        if (to === "visual") {
          // Set innerHTML directly
          if (this._visualEl) {
            this._visualEl.innerHTML = rawHtml || "<p><br></p>";
          }
        } else if (to === "markdown") {
          // Client-side HTML→markdown conversion
          var mdTa = this._getMarkdownTextarea();
          if (mdTa) mdTa.value = htmlToMarkdown(rawHtml);
        }
      }
    },

    _getMarkdownTextarea: function () {
      return document.getElementById(
        this._editorId + "-markdown-textarea"
      );
    },

    // -- Toolbar --

    _setupToolbar: function () {
      var self = this;
      var buttons = this.el.querySelectorAll("[data-toolbar-action]");

      buttons.forEach(function (btn) {
        btn.addEventListener("mousedown", function (e) {
          e.preventDefault();
        });

        btn.addEventListener("click", function (e) {
          e.preventDefault();
          var action = btn.dataset.toolbarAction;
          self._execToolbarAction(action);
        });
      });

      // Toolbar dropdowns: toggle menus without stealing editor focus
      var dropdowns = [
        { trigger: "[data-heading-trigger]", menu: "[data-heading-menu]" },
        { trigger: "[data-inline-more-trigger]", menu: "[data-inline-more-menu]" },
        { trigger: "[data-table-trigger]", menu: "[data-table-menu]" },
        { trigger: "[data-insert-more-trigger]", menu: "[data-insert-more-menu]" },
      ];
      dropdowns.forEach(function (cfg) {
        var trigger = self.el.querySelector(cfg.trigger);
        var menu = self.el.querySelector(cfg.menu);
        if (!trigger || !menu) return;
        trigger.addEventListener("mousedown", function (e) { e.preventDefault(); });
        menu.addEventListener("mousedown", function (e) { e.preventDefault(); });
        trigger.addEventListener("click", function (e) {
          e.preventDefault();
          // Close other dropdown menus first
          dropdowns.forEach(function (other) {
            if (other.menu !== cfg.menu) {
              var otherMenu = self.el.querySelector(other.menu);
              if (otherMenu) otherMenu.classList.add("hidden");
            }
          });
          menu.classList.toggle("hidden");
        });
        menu.querySelectorAll("[data-toolbar-action]").forEach(function (btn) {
          btn.addEventListener("click", function () { menu.classList.add("hidden"); });
        });
        document.addEventListener("mousedown", function (e) {
          if (!trigger.contains(e.target) && !menu.contains(e.target)) {
            menu.classList.add("hidden");
          }
        });
      });

      // Image dropdown: rendered on body with a backdrop to sit above navbars
      var imgTrigger = self.el.querySelector("[data-image-dropdown-trigger]");
      var imgMenu = self.el.querySelector("[data-image-dropdown-menu]");
      if (imgTrigger && imgMenu) {
        imgMenu.remove();
        imgMenu.style.position = "fixed";
        imgMenu.style.zIndex = "100000";
        document.body.appendChild(imgMenu);
        this._imageDropdownMenu = imgMenu;

        imgTrigger.addEventListener("mousedown", function (e) { e.preventDefault(); });
        imgMenu.addEventListener("mousedown", function (e) { e.preventDefault(); });

        imgTrigger.addEventListener("click", function (e) {
          e.preventDefault();
          dropdowns.forEach(function (cfg) {
            var otherMenu = self.el.querySelector(cfg.menu);
            if (otherMenu) otherMenu.classList.add("hidden");
          });

          if (imgMenu.classList.contains("hidden")) {
            // Show backdrop + menu
            var backdrop = document.createElement("div");
            backdrop.className = "leaf-image-url-backdrop";
            backdrop.addEventListener("click", function () {
              imgMenu.classList.add("hidden");
              backdrop.remove();
              self._imageDropdownBackdrop = null;
            });
            document.body.appendChild(backdrop);
            self._imageDropdownBackdrop = backdrop;

            var rect = imgTrigger.getBoundingClientRect();
            imgMenu.style.left = rect.left + "px";
            imgMenu.style.top = (rect.bottom + 2) + "px";
            imgMenu.classList.remove("hidden");
          } else {
            imgMenu.classList.add("hidden");
            if (self._imageDropdownBackdrop) {
              self._imageDropdownBackdrop.remove();
              self._imageDropdownBackdrop = null;
            }
          }
        });

        imgMenu.querySelectorAll("[data-toolbar-action]").forEach(function (btn) {
          btn.addEventListener("click", function () {
            imgMenu.classList.add("hidden");
            if (self._imageDropdownBackdrop) {
              self._imageDropdownBackdrop.remove();
              self._imageDropdownBackdrop = null;
            }
          });
        });
      }

      document.addEventListener("selectionchange", function () {
        if (self._mode === "visual" && self._visualEl) {
          var sel = window.getSelection();
          if (
            sel.rangeCount > 0 &&
            self._visualEl.contains(sel.anchorNode)
          ) {
            self._updateToolbarState();
          }
        }
      });
    },

    // -- Sticky toolbar --

    _getStickyTopOffset: function () {
      var maxBottom = 0;
      var candidates = document.querySelectorAll(
        "header, nav, [data-navbar], .navbar"
      );
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        var style = window.getComputedStyle(el);
        var pos = style.position;
        if (
          (pos === "fixed" || pos === "sticky") &&
          parseInt(style.top, 10) <= 0
        ) {
          var bottom = el.getBoundingClientRect().bottom;
          if (bottom > maxBottom) maxBottom = bottom;
        }
      }
      return maxBottom;
    },

    _setupStickyToolbar: function () {
      var self = this;
      this._stickyToolbarEl = this.el.querySelector("[data-visual-toolbar]");
      if (!this._stickyToolbarEl) return;

      // Create placeholder to prevent layout shift when toolbar becomes fixed
      this._stickyPlaceholder = document.createElement("div");
      this._stickyPlaceholder.className = "leaf-toolbar-placeholder";
      this._stickyPlaceholder.style.display = "none";
      this._stickyToolbarEl.parentNode.insertBefore(
        this._stickyPlaceholder,
        this._stickyToolbarEl
      );

      this._stickyScrollHandler = function () {
        var toolbar = self._stickyToolbarEl;
        var placeholder = self._stickyPlaceholder;
        var editorRect = self.el.getBoundingClientRect();
        var toolbarHeight = toolbar.offsetHeight;
        var topOffset = self._getStickyTopOffset();

        // Use placeholder position as the toolbar's natural position when sticky
        var isSticky = toolbar.classList.contains("leaf-toolbar-sticky");
        var refRect = isSticky
          ? placeholder.getBoundingClientRect()
          : toolbar.getBoundingClientRect();

        if (
          refRect.top < topOffset &&
          editorRect.bottom > toolbarHeight + topOffset
        ) {
          if (!isSticky) {
            placeholder.style.height = toolbarHeight + "px";
            placeholder.style.display = "block";
            toolbar.style.width = self.el.offsetWidth + "px";
            toolbar.style.top = topOffset + "px";
            toolbar.classList.add("leaf-toolbar-sticky");
          } else {
            // Update width and top offset on resize
            toolbar.style.width = self.el.offsetWidth + "px";
            toolbar.style.top = topOffset + "px";
          }
        } else {
          if (isSticky) {
            toolbar.classList.remove("leaf-toolbar-sticky");
            toolbar.style.width = "";
            toolbar.style.top = "";
            placeholder.style.display = "none";
          }
        }
      };

      window.addEventListener("scroll", this._stickyScrollHandler, {
        passive: true,
      });
      window.addEventListener("resize", this._stickyScrollHandler, {
        passive: true,
      });
    },

    _cleanupStickyToolbar: function () {
      if (this._stickyScrollHandler) {
        window.removeEventListener("scroll", this._stickyScrollHandler);
        window.removeEventListener("resize", this._stickyScrollHandler);
        this._stickyScrollHandler = null;
      }
      if (this._stickyPlaceholder && this._stickyPlaceholder.parentNode) {
        this._stickyPlaceholder.parentNode.removeChild(this._stickyPlaceholder);
        this._stickyPlaceholder = null;
      }
      if (this._stickyToolbarEl) {
        this._stickyToolbarEl.classList.remove("leaf-toolbar-sticky");
        this._stickyToolbarEl.style.width = "";
        this._stickyToolbarEl.style.top = "";
        this._stickyToolbarEl = null;
      }
    },

    _execToolbarAction: function (action) {
      if (this._readonly) return;

      if (this._mode === "markdown") {
        this._execMarkdownToolbarAction(action);
        return;
      }

      if (!this._visualEl) return;
      this._visualEl.focus({ preventScroll: true });

      switch (action) {
        case "bold":
          if (!this._isInsideHeading()) document.execCommand("bold", false, null);
          break;
        case "italic":
          document.execCommand("italic", false, null);
          break;
        case "strike":
          document.execCommand("strikeThrough", false, null);
          break;
        case "superscript":
          document.execCommand("superscript", false, null);
          break;
        case "subscript":
          document.execCommand("subscript", false, null);
          break;
        case "code":
          this._wrapSelectionWith("code");
          break;
        case "heading1":
          this._toggleHeading("h1");
          break;
        case "heading2":
          this._toggleHeading("h2");
          break;
        case "heading3":
          this._toggleHeading("h3");
          break;
        case "heading4":
          this._toggleHeading("h4");
          break;
        case "bulletList":
          document.execCommand("insertUnorderedList", false, null);
          break;
        case "orderedList":
          document.execCommand("insertOrderedList", false, null);
          break;
        case "indent":
          document.execCommand("indent", false, null);
          break;
        case "outdent":
          document.execCommand("outdent", false, null);
          break;
        case "blockquote":
          this._toggleBlockquote();
          break;
        case "codeBlock":
          document.execCommand("formatBlock", false, "pre");
          break;
        case "horizontalRule":
          document.execCommand("insertHorizontalRule", false, null);
          break;
        case "table":
          this._insertTable();
          break;
        case "tableAddRow":
          this._tableAddRow();
          break;
        case "tableRemoveRow":
          this._tableRemoveRow();
          break;
        case "tableAddCol":
          this._tableAddCol();
          break;
        case "tableRemoveCol":
          this._tableRemoveCol();
          break;
        case "link":
          this._insertLink();
          break;
        case "emoji":
          this._openEmojiPicker();
          return; // skip updateToolbarState/push — picker handles it
        case "insert-image":
          if (this._hasUpload) {
            this.pushEventTo(this.el, "insert_request", {
              editor_id: this._editorId,
              type: "image",
            });
          } else {
            this._openImageUrlDialog();
            return;
          }
          break;
        case "insert-image-upload":
          this.pushEventTo(this.el, "insert_request", {
            editor_id: this._editorId,
            type: "image",
          });
          break;
        case "insert-image-url":
          this._openImageUrlDialog();
          return;
        case "insert-video":
          this.pushEventTo(this.el, "insert_request", {
            editor_id: this._editorId,
            type: "video",
          });
          break;
        case "undo":
          document.execCommand("undo", false, null);
          break;
        case "redo":
          document.execCommand("redo", false, null);
          break;
        case "removeFormat":
          document.execCommand("removeFormat", false, null);
          document.execCommand("formatBlock", false, "p");
          break;
      }

      this._updateToolbarState();
      this._debouncedPushVisualChange();
    },

    _execMarkdownToolbarAction: function (action) {
      var gid = this._editorId.replace(/-/g, "_") + "_markdown";
      var fmt = window["markdownFormat_" + gid];
      var pfx = window["markdownLinePrefix_" + gid];
      var lnk = window["markdownLink_" + gid];
      var ins = window["markdownEditorInsert_" + gid];

      switch (action) {
        case "bold": if (fmt) fmt("**", "**"); break;
        case "italic": if (fmt) fmt("*", "*"); break;
        case "strike": if (fmt) fmt("~~", "~~"); break;
        case "superscript": if (fmt) fmt("<sup>", "</sup>"); break;
        case "subscript": if (fmt) fmt("<sub>", "</sub>"); break;
        case "code": if (fmt) fmt("`", "`"); break;
        case "heading1": if (pfx) pfx("# "); break;
        case "heading2": if (pfx) pfx("## "); break;
        case "heading3": if (pfx) pfx("### "); break;
        case "heading4": if (pfx) pfx("#### "); break;
        case "bulletList": if (pfx) pfx("- "); break;
        case "orderedList": if (pfx) pfx("1. "); break;
        case "indent": { var ind = window["markdownIndent_" + gid]; if (ind) ind("indent"); break; }
        case "outdent": { var ind = window["markdownIndent_" + gid]; if (ind) ind("outdent"); break; }
        case "blockquote": if (pfx) pfx("> "); break;
        case "codeBlock": if (fmt) fmt("```\n", "\n```"); break;
        case "horizontalRule": if (ins) ins("\n---\n"); break;
        case "table": if (ins) ins("\n| Header 1 | Header 2 |\n| --- | --- |\n| Cell 1 | Cell 2 |\n| Cell 3 | Cell 4 |\n"); break;
        case "link": if (lnk) lnk(); break;
        case "emoji": this._openEmojiPicker(); break;
        case "insert-image":
          if (this._hasUpload) {
            this.pushEventTo(this.el, "insert_request", { editor_id: this._editorId, type: "image" });
          } else {
            this._openImageUrlDialog();
          }
          break;
        case "insert-image-upload":
          this.pushEventTo(this.el, "insert_request", { editor_id: this._editorId, type: "image" });
          break;
        case "insert-image-url": this._openImageUrlDialog(); break;
        case "insert-video": this.pushEventTo(this.el, "insert_request", { editor_id: this._editorId, type: "video" }); break;
        case "removeFormat": break;
        case "undo": break;
        case "redo": break;
      }
    },

    _toggleHeading: function (tag) {
      var block = this._getCurrentBlock();
      if (block && block.tagName && block.tagName.toLowerCase() === tag) {
        document.execCommand("formatBlock", false, "p");
      } else {
        document.execCommand("formatBlock", false, tag);
      }
    },

    _toggleBlockquote: function () {
      var block = this._getCurrentBlock();
      if (
        block &&
        block.tagName &&
        block.tagName.toLowerCase() === "blockquote"
      ) {
        document.execCommand("formatBlock", false, "p");
      } else {
        document.execCommand("formatBlock", false, "blockquote");
      }
    },

    // -- Emoji Picker --

    _emojiCategories: [
      { name: "Smileys", emojis: ["😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊","😇","🥰","😍","🤩","😘","😗","😚","😙","🥲","😋","😛","😜","🤪","😝","🤑","🤗","🤭","🤫","🤔","🫡","🤐","🤨","😐","😑","😶","🫥","😏","😒","🙄","😬","🤥","😌","😔","😪","🤤","😴","😷","🤒","🤕","🤢","🤮","🥴","😵","🤯","🥳","🥸","😎","🤓","🧐"] },
      { name: "Gestures", emojis: ["👋","🤚","🖐","✋","🖖","🫱","🫲","🫳","🫴","👌","🤌","🤏","✌️","🤞","🫰","🤟","🤘","🤙","👈","👉","👆","🖕","👇","☝️","🫵","👍","👎","✊","👊","🤛","🤜","👏","🙌","🫶","👐","🤲","🤝","🙏"] },
      { name: "Hearts", emojis: ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❤️‍🔥","❤️‍🩹","❣️","💕","💞","💓","💗","💖","💘","💝","💟"] },
      { name: "Animals", emojis: ["🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐻‍❄️","🐨","🐯","🦁","🐮","🐷","🐸","🐵","🐔","🐧","🐦","🐤","🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞"] },
      { name: "Food", emojis: ["🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🥑","🍕","🍔","🍟","🌭","🍿","🧁","🍰","🎂","🍩","🍪","🍫","🍬","☕","🍵","🥤","🍺","🍷"] },
      { name: "Travel", emojis: ["🚗","🚕","🚌","🏎","🚑","🚒","✈️","🚀","🛸","🚁","⛵","🚢","🏠","🏢","🏥","🏫","⛪","🕌","🗼","🗽","⛲","🌋","🏔","🏖","🏕"] },
      { name: "Objects", emojis: ["⌚","📱","💻","⌨️","🖥","🖨","🖱","💾","💿","📷","📹","🎥","📺","📻","🎙","⏰","🔋","🔌","💡","🔦","🕯","💰","💳","💎","🔧","🔨","🔩","⚙️","📎","📌","✂️","🔑","🗝","🔒","🔓"] },
      { name: "Symbols", emojis: ["✅","❌","❓","❗","💯","🔥","⭐","🌟","✨","💫","💥","💢","💤","🎵","🎶","🔔","🔕","📣","💬","💭","🏁","🚩","🎯","♻️","⚠️","🚫","❎","✳️","❇️","🔴","🟠","🟡","🟢","🔵","🟣","⚫","⚪"] }
    ],

    _openEmojiPicker: function () {
      var self = this;

      // Close if already open
      if (this._emojiPicker) {
        this._closeEmojiPicker();
        return;
      }

      // Save selection so we can restore it after picking
      var sel = window.getSelection();
      if (sel.rangeCount > 0) {
        this._savedRange = sel.getRangeAt(0).cloneRange();
      }

      var btn = this.el.querySelector('[data-toolbar-action="emoji"]');
      if (!btn) return;

      var picker = document.createElement("div");
      picker.className = "leaf-emoji-picker";
      picker.style.cssText = "position:absolute;z-index:50;background:var(--color-base-200, #e5e7eb);color:var(--color-base-content, #1f2937);border:1px solid var(--color-base-300, #d1d5db);border-radius:0.5rem;box-shadow:0 4px 16px rgba(0,0,0,0.12), 0 1px 4px rgba(0,0,0,0.08);padding:0.5rem;width:320px;max-height:360px;display:flex;flex-direction:column;";

      // Search input
      var searchWrap = document.createElement("div");
      searchWrap.style.cssText = "margin-bottom:0.375rem;";
      var searchInput = document.createElement("input");
      searchInput.type = "text";
      searchInput.placeholder = "Search emoji...";
      searchInput.className = "input input-xs input-bordered w-full";
      searchInput.style.cssText = "font-size:0.8rem;";
      searchWrap.appendChild(searchInput);
      picker.appendChild(searchWrap);

      // Category tabs
      var tabsWrap = document.createElement("div");
      tabsWrap.style.cssText = "display:flex;gap:2px;margin-bottom:0.375rem;overflow-x:auto;flex-shrink:0;padding:0.25rem 0.125rem;border-bottom:1px solid var(--color-base-300, #d1d5db);";
      picker.appendChild(tabsWrap);

      // Grid container
      var gridWrap = document.createElement("div");
      gridWrap.style.cssText = "overflow-y:auto;flex:1;";
      picker.appendChild(gridWrap);

      var categories = this._emojiCategories;
      var activeCategory = 0;

      function renderGrid(emojis) {
        gridWrap.innerHTML = "";
        var grid = document.createElement("div");
        grid.style.cssText = "display:grid;grid-template-columns:repeat(8,1fr);gap:2px;";
        emojis.forEach(function (emoji) {
          var span = document.createElement("span");
          span.textContent = emoji;
          span.style.cssText = "cursor:pointer;font-size:1.25rem;text-align:center;padding:3px;border-radius:4px;line-height:1;";
          span.addEventListener("mouseover", function () { span.style.background = "color-mix(in oklab, var(--color-base-content, #1f2937) 8%, transparent)"; });
          span.addEventListener("mouseout", function () { span.style.background = ""; });
          span.addEventListener("click", function (e) {
            e.preventDefault();
            e.stopPropagation();
            self._insertEmoji(emoji);
          });
          grid.appendChild(span);
        });
        gridWrap.appendChild(grid);
      }

      function renderTabs() {
        tabsWrap.innerHTML = "";
        categories.forEach(function (cat, i) {
          var tab = document.createElement("button");
          tab.type = "button";
          tab.textContent = cat.emojis[0];
          tab.title = cat.name;
          tab.style.cssText = "cursor:pointer;font-size:1.125rem;padding:4px 6px;border-radius:6px;border:none;background:" + (i === activeCategory ? "color-mix(in oklab, var(--color-base-content, #1f2937) 12%, transparent)" : "none") + ";line-height:1;transition:background 0.1s;";
          tab.addEventListener("click", function (e) {
            e.preventDefault();
            e.stopPropagation();
            activeCategory = i;
            searchInput.value = "";
            renderTabs();
            renderGrid(categories[i].emojis);
          });
          tabsWrap.appendChild(tab);
        });
      }

      // Search filtering
      searchInput.addEventListener("input", function () {
        var q = searchInput.value.toLowerCase().trim();
        if (!q) {
          renderTabs();
          renderGrid(categories[activeCategory].emojis);
          return;
        }
        // Flatten all emojis for search (simple: show all since emoji chars aren't searchable by name easily)
        var all = [];
        categories.forEach(function (cat) {
          if (cat.name.toLowerCase().indexOf(q) !== -1) {
            all = all.concat(cat.emojis);
          }
        });
        if (all.length === 0) {
          categories.forEach(function (cat) { all = all.concat(cat.emojis); });
        }
        renderGrid(all);
      });

      // Prevent picker clicks from stealing editor focus
      picker.addEventListener("mousedown", function (e) {
        e.preventDefault();
      });

      renderTabs();
      renderGrid(categories[0].emojis);

      // Position below the emoji button
      var rect = btn.getBoundingClientRect();
      var toolbarRect = btn.closest("[data-visual-toolbar]").getBoundingClientRect();
      picker.style.left = Math.max(0, rect.left - toolbarRect.left) + "px";
      picker.style.top = (rect.bottom - toolbarRect.top + 4) + "px";

      btn.closest("[data-visual-toolbar]").style.position = "relative";
      btn.closest("[data-visual-toolbar]").appendChild(picker);
      this._emojiPicker = picker;

      // Close on outside click
      var closeHandler = function (e) {
        if (!picker.contains(e.target) && e.target !== btn) {
          self._closeEmojiPicker();
        }
      };
      setTimeout(function () {
        document.addEventListener("click", closeHandler);
      }, 0);
      this._emojiCloseHandler = closeHandler;

      searchInput.focus();
    },

    _closeEmojiPicker: function () {
      if (this._emojiPicker) {
        this._emojiPicker.remove();
        this._emojiPicker = null;
      }
      if (this._emojiCloseHandler) {
        document.removeEventListener("click", this._emojiCloseHandler);
        this._emojiCloseHandler = null;
      }
    },

    _insertEmoji: function (emoji) {
      if (this._mode === "markdown") {
        // Insert into markdown textarea
        var gid = this._editorId.replace(/-/g, "_") + "_markdown";
        var ins = window["markdownEditorInsert_" + gid];
        if (ins) ins(emoji);
        return;
      }

      // Visual mode: restore saved selection and insert
      if (this._visualEl) {
        this._visualEl.focus();
        if (this._savedRange) {
          var sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(this._savedRange);
          this._savedRange = null;
        }
        document.execCommand("insertText", false, emoji);
        this._debouncedPushVisualChange();
      }
    },

    _isInsideHeading: function () {
      var block = this._getCurrentBlock();
      if (!block || !block.tagName) return false;
      return /^h[1-6]$/i.test(block.tagName);
    },

    _getCurrentBlock: function () {
      var sel = window.getSelection();
      if (!sel.rangeCount) return null;
      var node = sel.anchorNode;
      while (node && node !== this._visualEl) {
        if (node.nodeType === Node.ELEMENT_NODE) {
          var display = window.getComputedStyle(node).display;
          if (display === "block" || display === "list-item") {
            return node;
          }
        }
        node = node.parentNode;
      }
      return null;
    },

    _insertLink: function () {
      var selection = window.getSelection();
      var currentHref = "";

      if (selection.rangeCount > 0) {
        var node = selection.anchorNode;
        while (node && node !== this._visualEl) {
          if (node.tagName && node.tagName.toLowerCase() === "a") {
            currentHref = node.getAttribute("href") || "";
            break;
          }
          node = node.parentNode;
        }
      }

      var url = prompt("Enter URL:", currentHref || "https://");
      if (url === null) return;

      if (url === "") {
        document.execCommand("unlink", false, null);
      } else {
        document.execCommand("createLink", false, url);
      }
    },

    _wrapSelectionWith: function (tagName) {
      var selection = window.getSelection();
      if (!selection.rangeCount) return;

      var range = selection.getRangeAt(0);
      var selectedText = range.toString();

      if (selectedText.length === 0) return;

      var parent = range.commonAncestorContainer;
      if (parent.nodeType === Node.TEXT_NODE) parent = parent.parentElement;
      if (
        parent &&
        parent.tagName &&
        parent.tagName.toLowerCase() === tagName
      ) {
        var text = document.createTextNode(parent.textContent);
        parent.parentNode.replaceChild(text, parent);
        return;
      }

      try {
        var el = document.createElement(tagName);
        range.surroundContents(el);
      } catch (_e) {
        var escaped = selectedText
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;");
        document.execCommand(
          "insertHTML",
          false,
          "<" + tagName + ">" + escaped + "</" + tagName + ">"
        );
      }
    },

    _insertTable: function () {
      var html =
        "<table><thead><tr><th>Header 1</th><th>Header 2</th></tr></thead>" +
        "<tbody><tr><td>Cell 1</td><td>Cell 2</td></tr>" +
        "<tr><td>Cell 3</td><td>Cell 4</td></tr></tbody></table><p><br></p>";
      document.execCommand("insertHTML", false, html);
    },

    _getTableContext: function () {
      var sel = window.getSelection();
      if (!sel.rangeCount) return null;
      var node = sel.anchorNode;
      if (node && node.nodeType === Node.TEXT_NODE) node = node.parentElement;
      var cell = node ? node.closest("td, th") : null;
      if (!cell) return null;
      var row = cell.parentElement;
      var table = cell.closest("table");
      if (!table || !this._visualEl.contains(table)) return null;
      var colIndex = Array.prototype.indexOf.call(row.children, cell);
      return { table: table, row: row, cell: cell, colIndex: colIndex };
    },

    _tableAddRow: function () {
      var ctx = this._getTableContext();
      if (!ctx) return;
      var cols = ctx.row.children.length;
      var newRow = document.createElement("tr");
      for (var i = 0; i < cols; i++) {
        var td = document.createElement("td");
        td.innerHTML = "<br>";
        newRow.appendChild(td);
      }
      // Insert after current row; if in thead, append to tbody instead
      if (ctx.row.parentElement.tagName.toLowerCase() === "thead") {
        var tbody = ctx.table.querySelector("tbody");
        if (!tbody) {
          tbody = document.createElement("tbody");
          ctx.table.appendChild(tbody);
        }
        tbody.insertBefore(newRow, tbody.firstChild);
      } else {
        ctx.row.parentNode.insertBefore(newRow, ctx.row.nextSibling);
      }
    },

    _tableRemoveRow: function () {
      var ctx = this._getTableContext();
      if (!ctx) return;
      var allRows = ctx.table.querySelectorAll("tr");
      if (allRows.length <= 1) {
        // Last row — remove the entire table
        ctx.table.parentNode.removeChild(ctx.table);
        return;
      }
      // Don't allow removing the header row if it's the only one in thead
      if (ctx.row.parentElement.tagName.toLowerCase() === "thead") return;
      ctx.row.parentNode.removeChild(ctx.row);
    },

    _tableAddCol: function () {
      var ctx = this._getTableContext();
      if (!ctx) return;
      var rows = ctx.table.querySelectorAll("tr");
      var insertAt = ctx.colIndex + 1;
      for (var i = 0; i < rows.length; i++) {
        var isHeader = rows[i].parentElement.tagName.toLowerCase() === "thead";
        var newCell = document.createElement(isHeader ? "th" : "td");
        newCell.innerHTML = "<br>";
        var cells = rows[i].children;
        if (insertAt < cells.length) {
          rows[i].insertBefore(newCell, cells[insertAt]);
        } else {
          rows[i].appendChild(newCell);
        }
      }
    },

    _tableRemoveCol: function () {
      var ctx = this._getTableContext();
      if (!ctx) return;
      var rows = ctx.table.querySelectorAll("tr");
      var colCount = rows[0] ? rows[0].children.length : 0;
      if (colCount <= 1) {
        // Last column — remove the entire table
        ctx.table.parentNode.removeChild(ctx.table);
        return;
      }
      for (var i = 0; i < rows.length; i++) {
        var cell = rows[i].children[ctx.colIndex];
        if (cell) rows[i].removeChild(cell);
      }
    },

    _updateToolbarState: function () {
      var self = this;
      var block = this._getCurrentBlock();
      var blockTag =
        block && block.tagName ? block.tagName.toLowerCase() : "";

      var buttons = this.el.querySelectorAll("[data-toolbar-action]");
      buttons.forEach(function (btn) {
        var action = btn.dataset.toolbarAction;
        var active = false;

        switch (action) {
          case "bold":
            active = document.queryCommandState("bold") || /^h[1-6]$/.test(blockTag);
            break;
          case "italic":
            active = document.queryCommandState("italic");
            break;
          case "strike":
            active = document.queryCommandState("strikeThrough");
            break;
          case "superscript":
            active = document.queryCommandState("superscript");
            break;
          case "subscript":
            active = document.queryCommandState("subscript");
            break;
          case "orderedList":
            active = document.queryCommandState("insertOrderedList");
            break;
          case "bulletList":
            active = document.queryCommandState("insertUnorderedList");
            break;
          case "heading1":
            active = blockTag === "h1";
            break;
          case "heading2":
            active = blockTag === "h2";
            break;
          case "heading3":
            active = blockTag === "h3";
            break;
          case "heading4":
            active = blockTag === "h4";
            break;
          case "blockquote":
            active = blockTag === "blockquote";
            break;
          case "codeBlock":
            active = blockTag === "pre";
            break;
          case "link":
            active = self._isInsideTag("a");
            break;
          case "code":
            active = self._isInsideTag("code");
            break;
        }

        if (active) {
          btn.classList.add("btn-active");
        } else {
          btn.classList.remove("btn-active");
        }
      });
    },

    _isInsideTag: function (tagName) {
      var sel = window.getSelection();
      if (!sel.rangeCount) return false;
      var node = sel.anchorNode;
      while (node && node !== this._visualEl) {
        if (
          node.tagName &&
          node.tagName.toLowerCase() === tagName
        ) {
          return true;
        }
        node = node.parentNode;
      }
      return false;
    },

    // -- Link popover --

    _setupLinkPopover: function () {
      if (!this._visualEl) return;
      var self = this;

      this._linkPopoverEl = null;
      this._linkPopoverAnchor = null;
      this._imagePopoverEl = null;
      this._imagePopoverTarget = null;

      this._visualEl.addEventListener("click", function (e) {
        if (self._readonly) return;

        var target = e.target;

        // Check if clicked on an <img>
        if (target.tagName && target.tagName.toLowerCase() === "img") {
          e.preventDefault();
          self._dismissLinkPopover();
          self._showImagePopover(target);
          return;
        }

        // Walk up from click target to find an <a> inside the editor
        var node = target;
        var anchor = null;
        while (node && node !== self._visualEl) {
          if (node.tagName && node.tagName.toLowerCase() === "a") {
            anchor = node;
            break;
          }
          node = node.parentNode;
        }

        if (anchor) {
          e.preventDefault();
          self._dismissImagePopover();
          self._showLinkPopover(anchor);
        } else {
          self._dismissLinkPopover();
          self._dismissImagePopover();
        }
      });

      // Dismiss when clicking outside the editor + popovers
      this._onDocClickForPopover = function (e) {
        if (self._linkPopoverEl && !self._linkPopoverEl.contains(e.target) &&
            !self._visualEl.contains(e.target)) {
          self._dismissLinkPopover();
        }
        if (self._imagePopoverEl && !self._imagePopoverEl.contains(e.target) &&
            !self._visualEl.contains(e.target)) {
          self._dismissImagePopover();
        }
      };
      document.addEventListener("mousedown", this._onDocClickForPopover);
    },

    _showLinkPopover: function (anchorEl) {
      this._dismissLinkPopover();
      this._linkPopoverAnchor = anchorEl;

      var href = anchorEl.getAttribute("href") || "";
      var self = this;

      // Build popover
      var pop = document.createElement("div");
      pop.className = "leaf-link-popover";

      // Link icon
      var linkIcon = document.createElement("span");
      linkIcon.style.cssText = "display:flex;align-items:center;opacity:0.5;flex-shrink:0;";
      linkIcon.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path fill-rule="evenodd" d="M8.914 6.025a.75.75 0 0 1 1.06 0 3.5 3.5 0 0 1 0 4.95l-2 2a3.5 3.5 0 0 1-5.396-4.402.75.75 0 0 1 1.251.827 2 2 0 0 0 3.085 2.514l2-2a2 2 0 0 0 0-2.828.75.75 0 0 1 0-1.06Z" clip-rule="evenodd"/><path fill-rule="evenodd" d="M7.086 9.975a.75.75 0 0 1-1.06 0 3.5 3.5 0 0 1 0-4.95l2-2a3.5 3.5 0 0 1 5.396 4.402.75.75 0 0 1-1.251-.827 2 2 0 0 0-3.085-2.514l-2 2a2 2 0 0 0 0 2.828.75.75 0 0 1 0 1.06Z" clip-rule="evenodd"/></svg>';
      pop.appendChild(linkIcon);

      // URL display/link
      var urlLink = document.createElement("a");
      urlLink.href = href;
      urlLink.target = "_blank";
      urlLink.rel = "noopener";
      urlLink.textContent = href || "(no url)";
      urlLink.title = href;
      pop.appendChild(urlLink);

      // Actions group (pill within pill)
      var actions = document.createElement("span");
      actions.className = "leaf-popover-actions";

      // Edit button
      var editBtn = document.createElement("button");
      editBtn.type = "button";
      editBtn.title = "Edit link";
      editBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path d="M13.488 2.513a1.75 1.75 0 0 0-2.475 0L3.05 10.476a.75.75 0 0 0-.188.335l-.95 3.507a.75.75 0 0 0 .92.92l3.507-.95a.75.75 0 0 0 .335-.188l7.963-7.963a1.75 1.75 0 0 0 0-2.475l-.149-.149ZM11.72 3.22a.25.25 0 0 1 .354 0l.149.149a.25.25 0 0 1 0 .354L5.106 10.84l-1.575.427.427-1.575 7.11-7.11.652-.362Z"/></svg>';
      editBtn.addEventListener("mousedown", function (e) { e.preventDefault(); });
      editBtn.addEventListener("click", function (e) {
        e.preventDefault();
        e.stopPropagation();
        var newUrl = prompt("Edit URL:", href);
        if (newUrl === null) return;
        if (newUrl === "") {
          self._unwrapLink(anchorEl);
          self._dismissLinkPopover();
        } else {
          anchorEl.setAttribute("href", newUrl);
          urlLink.href = newUrl;
          urlLink.textContent = newUrl;
          urlLink.title = newUrl;
          href = newUrl;
        }
        self._debouncedPushVisualChange();
      });
      actions.appendChild(editBtn);

      // Divider inside actions
      var d1 = document.createElement("span");
      d1.className = "leaf-popover-divider";
      actions.appendChild(d1);

      // Remove button
      var removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.title = "Remove link";
      removeBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L6.94 8l-1.72 1.72a.75.75 0 1 0 1.06 1.06L8 9.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L9.06 8l1.72-1.72a.75.75 0 0 0-1.06-1.06L8 6.94 6.28 5.22Z"/></svg>';
      removeBtn.addEventListener("mousedown", function (e) { e.preventDefault(); });
      removeBtn.addEventListener("click", function (e) {
        e.preventDefault();
        e.stopPropagation();
        self._unwrapLink(anchorEl);
        self._dismissLinkPopover();
        self._debouncedPushVisualChange();
      });
      actions.appendChild(removeBtn);

      pop.appendChild(actions);

      // Position below the anchor element
      this.el.style.position = "relative";
      var editorRect = this.el.getBoundingClientRect();
      var anchorRect = anchorEl.getBoundingClientRect();

      pop.style.left = (anchorRect.left - editorRect.left) + "px";
      pop.style.top = (anchorRect.bottom - editorRect.top + 8) + "px";

      this.el.appendChild(pop);
      this._linkPopoverEl = pop;
    },

    _dismissLinkPopover: function () {
      if (this._linkPopoverEl) {
        this._linkPopoverEl.remove();
        this._linkPopoverEl = null;
        this._linkPopoverAnchor = null;
      }
    },

    _unwrapLink: function (anchorEl) {
      // Replace the <a> with its text content
      var parent = anchorEl.parentNode;
      while (anchorEl.firstChild) {
        parent.insertBefore(anchorEl.firstChild, anchorEl);
      }
      parent.removeChild(anchorEl);
    },

    // -- Image URL dialog --

    _openImageUrlDialog: function () {
      this._dismissImageUrlDialog();
      var self = this;

      // Save selection so we can restore it before inserting
      var savedRange = null;
      if (this._mode === "visual" && this._visualEl) {
        var sel = window.getSelection();
        if (sel.rangeCount > 0) {
          savedRange = sel.getRangeAt(0).cloneRange();
        }
      }

      var dialog = document.createElement("div");
      dialog.className = "leaf-image-url-dialog";

      var urlLabel = document.createElement("label");
      urlLabel.textContent = "Image URL";
      dialog.appendChild(urlLabel);

      var urlInput = document.createElement("input");
      urlInput.type = "text";
      urlInput.placeholder = "https://example.com/image.jpg";
      urlInput.addEventListener("mousedown", function (e) { e.stopPropagation(); });
      dialog.appendChild(urlInput);

      var altLabel = document.createElement("label");
      altLabel.textContent = "Alt text (optional)";
      dialog.appendChild(altLabel);

      var altInput = document.createElement("input");
      altInput.type = "text";
      altInput.placeholder = "Describe the image";
      altInput.addEventListener("mousedown", function (e) { e.stopPropagation(); });
      dialog.appendChild(altInput);

      var actions = document.createElement("div");
      actions.className = "leaf-image-url-actions";

      var cancelBtn = document.createElement("button");
      cancelBtn.type = "button";
      cancelBtn.className = "leaf-image-url-cancel";
      cancelBtn.textContent = "Cancel";
      cancelBtn.addEventListener("click", function () {
        self._dismissImageUrlDialog();
      });
      actions.appendChild(cancelBtn);

      var insertBtn = document.createElement("button");
      insertBtn.type = "button";
      insertBtn.className = "leaf-image-url-insert";
      insertBtn.textContent = "Insert";
      insertBtn.addEventListener("click", function () {
        var url = urlInput.value.trim();
        if (!url) return;
        var alt = altInput.value.trim();
        self._dismissImageUrlDialog();
        self._insertImageByUrl(url, alt, savedRange);
      });
      actions.appendChild(insertBtn);
      dialog.appendChild(actions);

      // Enter key in inputs triggers insert
      var handleKey = function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
          insertBtn.click();
        } else if (e.key === "Escape") {
          e.preventDefault();
          self._dismissImageUrlDialog();
        }
      };
      urlInput.addEventListener("keydown", handleKey);
      altInput.addEventListener("keydown", handleKey);

      // Position below the image button using fixed positioning on body
      var splitBtn = this.el.querySelector("[data-image-split-btn]");
      if (splitBtn) {
        var btnRect = splitBtn.getBoundingClientRect();
        dialog.style.left = btnRect.left + "px";
        dialog.style.top = (btnRect.bottom + 4) + "px";
      }

      // Backdrop
      var backdrop = document.createElement("div");
      backdrop.className = "leaf-image-url-backdrop";
      backdrop.addEventListener("click", function () {
        self._dismissImageUrlDialog();
      });
      document.body.appendChild(backdrop);
      this._imageUrlBackdrop = backdrop;
      this.pushEventTo(this.el, "media_ui_opened", { editor_id: this._editorId });
      document.body.appendChild(dialog);
      this._imageUrlDialog = dialog;
      urlInput.focus();
    },

    _dismissImageUrlDialog: function () {
      if (this._imageUrlDialog) {
        this._imageUrlDialog.remove();
        this._imageUrlDialog = null;
      }
      if (this._imageUrlBackdrop) {
        this._imageUrlBackdrop.remove();
        this._imageUrlBackdrop = null;
      }
      this.pushEventTo(this.el, "media_ui_closed", { editor_id: this._editorId });
    },


    _insertImageByUrl: function (url, alt, savedRange) {
      var escapedAlt = (alt || "").replace(/"/g, "&quot;");

      if (this._mode === "visual" && this._visualEl) {
        this._visualEl.focus();
        // Restore saved selection
        if (savedRange) {
          var sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(savedRange);
        }
        var imgHtml = '<img src="' + url + '" alt="' + escapedAlt + '" draggable="true" />';
        document.execCommand("insertHTML", false, imgHtml);
        this._debouncedPushVisualChange();
      } else if (this._mode === "markdown") {
        var gid = this._editorId.replace(/-/g, "_") + "_markdown";
        var ins = window["markdownEditorInsert_" + gid];
        if (ins) {
          var md = "![" + (alt || "") + "](" + url + ")";
          ins(md);
        }
      }
    },

    // -- Image selection + resize + popover --

    _showImagePopover: function (imgEl) {
      this._dismissImagePopover(true);
      this._imagePopoverTarget = imgEl;

      var src = imgEl.getAttribute("src") || "";
      var alt = imgEl.getAttribute("alt") || "";
      var self = this;

      // Mark image as selected (outline via CSS)
      imgEl.classList.add("leaf-img-selected");

      // Create resize handles
      this._resizeHandles = [];
      var corners = ["nw", "ne", "sw", "se"];
      corners.forEach(function (corner) {
        var handle = document.createElement("div");
        handle.className = "leaf-resize-handle leaf-resize-handle--" + corner;
        handle.setAttribute("data-corner", corner);
        handle.addEventListener("mousedown", function (e) {
          e.preventDefault();
          e.stopPropagation();
          self._startResize(e, imgEl, corner);
        });
        self.el.appendChild(handle);
        self._resizeHandles.push(handle);
      });

      this._positionResizeHandles(imgEl);

      // Build popover
      var pop = document.createElement("div");
      pop.className = "leaf-link-popover";

      // Image icon
      var imgIcon = document.createElement("span");
      imgIcon.style.cssText = "display:flex;align-items:center;opacity:0.5;flex-shrink:0;";
      imgIcon.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path fill-rule="evenodd" d="M2 4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V4Zm10.5 5.707L10.354 7.56a.5.5 0 0 0-.708 0L6.5 10.707 5.354 9.56a.5.5 0 0 0-.708 0L3.5 10.707V4a.5.5 0 0 1 .5-.5h8a.5.5 0 0 1 .5.5v5.707ZM11 6a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z" clip-rule="evenodd"/></svg>';
      pop.appendChild(imgIcon);

      // Alt text input
      var altInput = document.createElement("input");
      altInput.type = "text";
      altInput.value = alt;
      altInput.placeholder = "Alt text...";
      altInput.title = "Image alt text";
      altInput.style.cssText = [
        "background: color-mix(in oklab, var(--color-base-content, #1f2937) 8%, transparent);",
        "border: none; border-radius: 0.25rem; padding: 0.2rem 0.4rem;",
        "font-size: 0.8125rem; color: inherit; outline: none; width: 160px;",
      ].join("");
      altInput.addEventListener("mousedown", function (e) { e.stopPropagation(); });
      altInput.addEventListener("input", function () {
        imgEl.setAttribute("alt", altInput.value);
      });
      altInput.addEventListener("keydown", function (e) {
        if (e.key === "Escape") {
          self._dismissImagePopover();
        }
      });
      pop.appendChild(altInput);

      // Actions group
      var actions = document.createElement("span");
      actions.className = "leaf-popover-actions";

      // Open in new tab button
      var openBtn = document.createElement("button");
      openBtn.type = "button";
      openBtn.title = "Open image";
      openBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path d="M8.22 2.97a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06l2.97-2.97H3.75a.75.75 0 0 1 0-1.5h7.44L8.22 4.03a.75.75 0 0 1 0-1.06Z"/></svg>';
      openBtn.addEventListener("mousedown", function (e) { e.preventDefault(); });
      openBtn.addEventListener("click", function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (src) window.open(src, "_blank");
      });
      actions.appendChild(openBtn);

      // Edit src button
      var editSrcBtn = document.createElement("button");
      editSrcBtn.type = "button";
      editSrcBtn.title = "Edit image URL";
      editSrcBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path d="M13.488 2.513a1.75 1.75 0 0 0-2.475 0L3.05 10.476a.75.75 0 0 0-.188.335l-.95 3.507a.75.75 0 0 0 .92.92l3.507-.95a.75.75 0 0 0 .335-.188l7.963-7.963a1.75 1.75 0 0 0 0-2.475l-.149-.149ZM11.72 3.22a.25.25 0 0 1 .354 0l.149.149a.25.25 0 0 1 0 .354L5.106 10.84l-1.575.427.427-1.575 7.11-7.11.652-.362Z"/></svg>';
      editSrcBtn.addEventListener("mousedown", function (e) { e.preventDefault(); });
      editSrcBtn.addEventListener("click", function (e) {
        e.preventDefault();
        e.stopPropagation();
        var newSrc = prompt("Edit image URL:", src);
        if (newSrc === null) {
          self._showImagePopover(imgEl);
          return;
        }
        newSrc = newSrc.trim();
        if (newSrc) {
          imgEl.setAttribute("src", newSrc);
          src = newSrc;
        }
        self._showImagePopover(imgEl);
      });
      actions.appendChild(editSrcBtn);

      // Divider
      var d1 = document.createElement("span");
      d1.className = "leaf-popover-divider";
      actions.appendChild(d1);

      // Remove button
      var removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.title = "Remove image";
      removeBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="13" height="13"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L6.94 8l-1.72 1.72a.75.75 0 1 0 1.06 1.06L8 9.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L9.06 8l1.72-1.72a.75.75 0 0 0-1.06-1.06L8 6.94 6.28 5.22Z"/></svg>';
      removeBtn.addEventListener("mousedown", function (e) { e.preventDefault(); });
      removeBtn.addEventListener("click", function (e) {
        e.preventDefault();
        e.stopPropagation();
        imgEl.remove();
        self._dismissImagePopover();
        self._debouncedPushVisualChange();
      });
      actions.appendChild(removeBtn);

      pop.appendChild(actions);

      // Position below the image
      this.el.style.position = "relative";
      var editorRect = this.el.getBoundingClientRect();
      var imgRect = imgEl.getBoundingClientRect();

      pop.style.left = (imgRect.left - editorRect.left) + "px";
      pop.style.top = (imgRect.bottom - editorRect.top + 8) + "px";

      this.el.appendChild(pop);
      this._imagePopoverEl = pop;

      // Focus the alt input
      setTimeout(function () { altInput.focus(); altInput.select(); }, 50);
    },

    _positionResizeHandles: function (imgEl) {
      if (!this._resizeHandles || !imgEl) return;
      var editorRect = this.el.getBoundingClientRect();
      var imgRect = imgEl.getBoundingClientRect();
      var ox = imgRect.left - editorRect.left;
      var oy = imgRect.top - editorRect.top;
      var w = imgRect.width;
      var h = imgRect.height;
      var hs = 5; // half handle size

      var positions = {
        nw: { left: ox - hs, top: oy - hs },
        ne: { left: ox + w - hs, top: oy - hs },
        sw: { left: ox - hs, top: oy + h - hs },
        se: { left: ox + w - hs, top: oy + h - hs },
      };

      this._resizeHandles.forEach(function (handle) {
        var corner = handle.getAttribute("data-corner");
        var pos = positions[corner];
        handle.style.left = pos.left + "px";
        handle.style.top = pos.top + "px";
      });
    },

    _startResize: function (e, imgEl, corner) {
      var self = this;
      var startX = e.clientX;
      var startY = e.clientY;
      var startW = imgEl.offsetWidth;
      var startH = imgEl.offsetHeight;
      var aspect = startW / startH;

      function onMove(ev) {
        ev.preventDefault();
        var dx = ev.clientX - startX;
        var dy = ev.clientY - startY;
        var newW;

        // Use the axis with more movement, maintain aspect ratio
        if (corner === "se") {
          newW = Math.max(50, startW + dx);
        } else if (corner === "sw") {
          newW = Math.max(50, startW - dx);
        } else if (corner === "ne") {
          newW = Math.max(50, startW + dx);
        } else { // nw
          newW = Math.max(50, startW - dx);
        }

        var newH = newW / aspect;
        imgEl.style.width = newW + "px";
        imgEl.style.height = newH + "px";
        imgEl.setAttribute("width", Math.round(newW));
        imgEl.setAttribute("height", Math.round(newH));

        self._positionResizeHandles(imgEl);

        // Reposition popover below the image
        if (self._imagePopoverEl) {
          var editorRect = self.el.getBoundingClientRect();
          var imgRect = imgEl.getBoundingClientRect();
          self._imagePopoverEl.style.left = (imgRect.left - editorRect.left) + "px";
          self._imagePopoverEl.style.top = (imgRect.bottom - editorRect.top + 8) + "px";
        }
      }

      function onUp() {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
      }

      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    },

    // -- Block & image drag-and-drop reordering --

    _setupImageDragAndDrop: function () {
      if (!this._visualEl) return;
      var self = this;

      this._dragIndicator = null;
      this._dragSourceBlock = null;
      this._dragDropTarget = null;
      this._dragHandle = null;
      this._dragHandleBlock = null;

      // Ensure existing images are draggable
      var imgs = this._visualEl.querySelectorAll("img");
      for (var i = 0; i < imgs.length; i++) {
        imgs[i].setAttribute("draggable", "true");
      }

      // Watch for new images and mark them draggable
      this._imgObserver = new MutationObserver(function (mutations) {
        mutations.forEach(function (m) {
          m.addedNodes.forEach(function (node) {
            if (node.nodeType !== Node.ELEMENT_NODE) return;
            if (node.tagName && node.tagName.toLowerCase() === "img") {
              node.setAttribute("draggable", "true");
            }
            var childImgs = node.querySelectorAll && node.querySelectorAll("img");
            if (childImgs) {
              for (var j = 0; j < childImgs.length; j++) {
                childImgs[j].setAttribute("draggable", "true");
              }
            }
          });
        });
      });
      this._imgObserver.observe(this._visualEl, { childList: true, subtree: true });

      // -- Drag handle (grip icon) for block elements --

      var handle = this._visualWrapper.querySelector("[data-drag-handle]");
      this._dragHandle = handle;

      // Show handle on mousemove over blocks
      this._visualEl.addEventListener("mousemove", function (e) {
        if (self._readonly || self._dragSourceBlock) return;
        var block = self._getHoveredBlock(e.target);
        if (!block) return;
        // Always update if stale (e.g. after innerHTML replacement) or different block
        if (block !== self._dragHandleBlock || !self._dragHandleBlock.parentNode) {
          self._dragHandleBlock = block;
          self._positionDragHandle(block);
        }
      });

      // Show handle when hovering in the left margin area (outside content but inside wrapper)
      this._visualWrapper.addEventListener("mousemove", function (e) {
        if (self._readonly || self._dragSourceBlock) return;

        // Skip if mouse is over a content block - let the visualEl handler deal with it
        var hoveredBlock = self._getHoveredBlock(e.target);
        if (hoveredBlock) return;

        // Skip if mouse is over the drag handle itself
        if (e.target.closest("[data-drag-handle]")) return;

        // Find the block nearest to the mouse cursor vertically
        var wrapperRect = self._visualWrapper.getBoundingClientRect();
        var mouseY = e.clientY - wrapperRect.top;
        var nearestBlock = self._findBlockAtY(mouseY);

        if (nearestBlock && nearestBlock !== self._dragHandleBlock) {
          self._dragHandleBlock = nearestBlock;
          self._positionDragHandle(nearestBlock);
        }
      });

      // Hide handle when mouse leaves the wrapper, unless going to the handle or a block is selected
      this._visualWrapper.addEventListener("mouseleave", function (e) {
        // Don't hide if mouse is moving to the drag handle
        if (e.relatedTarget && e.relatedTarget.matches("[data-drag-handle]")) return;

        if (!self._dragSourceBlock && !self._imagePopoverTarget) {
          self._dragHandleBlock = null;
          self._dragHandle.style.display = "none";
        }
      });

      // -- Handle mousedown (block drag via mouse, delegated so it survives morphdom) --
      this._visualWrapper.addEventListener("mousedown", function (e) {
        if (!e.target.closest("[data-drag-handle]")) return;
        var block = self._dragHandleBlock;
        if (!block || self._readonly) return;
        e.preventDefault();
        e.stopPropagation();

        self._dismissImagePopover();
        self._dismissLinkPopover();

        self._dragSourceBlock = block;
        block.classList.add("leaf-dragging");
        self._dragHandle.style.cursor = "grabbing";

        self._createDropIndicator();

        function onMouseMove(ev) {
          ev.preventDefault();
          var target = self._findDropTarget(ev.clientY);
          if (target) {
            self._dragDropTarget = target;
            self._positionDropIndicator(target);
          }
        }

        function onMouseUp(ev) {
          document.removeEventListener("mousemove", onMouseMove);
          document.removeEventListener("mouseup", onMouseUp);
          self._dragHandle.style.cursor = "";

          if (self._dragSourceBlock && self._dragDropTarget) {
            var sourceEl = self._dragSourceBlock;
            var targetEl = self._dragDropTarget.element;
            var position = self._dragDropTarget.position;

            var refNext = targetEl.nextSibling;
            var refParent = targetEl.parentNode;
            var targetIsSource = (sourceEl === targetEl);

            sourceEl.remove();

            if (targetIsSource) {
              if (refNext && refNext.parentNode) {
                refParent.insertBefore(sourceEl, refNext);
              } else if (refParent) {
                refParent.appendChild(sourceEl);
              }
            } else if (!targetEl.parentNode) {
              if (refNext && refNext.parentNode) {
                refParent.insertBefore(sourceEl, refNext);
              } else if (refParent) {
                refParent.appendChild(sourceEl);
              }
            } else if (position === "before") {
              targetEl.parentNode.insertBefore(sourceEl, targetEl);
            } else {
              if (targetEl.nextSibling) {
                targetEl.parentNode.insertBefore(sourceEl, targetEl.nextSibling);
              } else {
                targetEl.parentNode.appendChild(sourceEl);
              }
            }

            self._debouncedPushVisualChange();
          }

          self._cleanupDrag();
        }

        document.addEventListener("mousemove", onMouseMove);
        document.addEventListener("mouseup", onMouseUp);
      });

      // -- Image native dragstart --
      this._visualEl.addEventListener("dragstart", function (e) {
        var img = e.target;
        if (!img || img.tagName.toLowerCase() !== "img") return;
        if (self._readonly) { e.preventDefault(); return; }

        // Don't drag if popover is open (resize handles active)
        if (self._imagePopoverTarget === img) {
          e.preventDefault();
          return;
        }

        self._dismissImagePopover();
        self._dismissLinkPopover();

        // For images, the drag source is the image itself (or its parent block)
        var block = self._getContainingBlock(img);
        self._dragSourceBlock = block || img;
        (block || img).classList.add("leaf-dragging");

        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", "leaf-image-drag");

        self._createDropIndicator();
      });

      // -- Image native drag: dragover/drop/dragleave/dragend --
      this._visualEl.addEventListener("dragover", function (e) {
        if (!self._dragSourceBlock) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";

        var target = self._findDropTarget(e.clientY);
        if (target) {
          self._dragDropTarget = target;
          self._positionDropIndicator(target);
        }
      });

      this._visualEl.addEventListener("dragleave", function (e) {
        if (!self._visualEl.contains(e.relatedTarget)) {
          if (self._dragIndicator) self._dragIndicator.style.display = "none";
          self._dragDropTarget = null;
        }
      });

      this._visualEl.addEventListener("drop", function (e) {
        e.preventDefault();
        if (!self._dragSourceBlock || !self._dragDropTarget) {
          self._cleanupDrag();
          return;
        }

        var sourceEl = self._dragSourceBlock;
        var targetEl = self._dragDropTarget.element;
        var position = self._dragDropTarget.position;

        var refNext = targetEl.nextSibling;
        var refParent = targetEl.parentNode;
        var targetIsSource = (sourceEl === targetEl);

        sourceEl.remove();

        if (targetIsSource) {
          if (refNext && refNext.parentNode) {
            refParent.insertBefore(sourceEl, refNext);
          } else if (refParent) {
            refParent.appendChild(sourceEl);
          }
        } else if (!targetEl.parentNode) {
          if (refNext && refNext.parentNode) {
            refParent.insertBefore(sourceEl, refNext);
          } else if (refParent) {
            refParent.appendChild(sourceEl);
          }
        } else if (position === "before") {
          targetEl.parentNode.insertBefore(sourceEl, targetEl);
        } else {
          if (targetEl.nextSibling) {
            targetEl.parentNode.insertBefore(sourceEl, targetEl.nextSibling);
          } else {
            targetEl.parentNode.appendChild(sourceEl);
          }
        }

        self._cleanupDrag();
        self._debouncedPushVisualChange();
      });

      this._visualEl.addEventListener("dragend", function () {
        self._cleanupDrag();
      });
    },

    _getHoveredBlock: function (target) {
      // Walk up from target to find the direct child of _visualEl
      var node = target;
      while (node && node.parentNode !== this._visualEl) {
        node = node.parentNode;
      }
      if (!node || node.nodeType !== Node.ELEMENT_NODE) return null;
      if (!this._isBlockTag(node)) return null;
      return node;
    },

    _getContainingBlock: function (node) {
      // Walk up from node to find the direct child of _visualEl
      var current = node;
      while (current && current.parentNode !== this._visualEl) {
        current = current.parentNode;
      }
      return current;
    },

    _isBlockTag: function (el) {
      var BLOCK_TAGS = {
        p: true, h1: true, h2: true, h3: true, h4: true, h5: true, h6: true,
        blockquote: true, pre: true, ul: true, ol: true, hr: true, img: true,
        div: true, figure: true, table: true
      };
      return el && el.tagName && BLOCK_TAGS[el.tagName.toLowerCase()];
    },

    _findBlockAtY: function (y) {
      var children = this._visualEl.childNodes;
      var best = null;
      var bestDist = Infinity;
      var wrapperRect = this._visualWrapper.getBoundingClientRect();

      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (child.nodeType !== Node.ELEMENT_NODE) continue;
        if (!this._isBlockTag(child)) continue;

        var rect = child.getBoundingClientRect();
        var marginTop = parseFloat(window.getComputedStyle(child).marginTop) || 0;
        var blockTop = rect.top - wrapperRect.top - marginTop;
        var blockBottom = rect.bottom - wrapperRect.top;

        // If mouse is within the block's range (including margin), it's a direct hit
        if (y >= blockTop && y <= blockBottom) {
          return child;
        }

        // Otherwise find nearest by distance to closest edge
        var dist = y < blockTop ? blockTop - y : y - blockBottom;
        if (dist < bestDist) {
          bestDist = dist;
          best = child;
        }
      }

      return best;
    },

    _positionDragHandle: function (block) {
      if (!this._dragHandle) return;
      var wrapperRect = this._visualWrapper.getBoundingClientRect();
      var blockRect = block.getBoundingClientRect();

      var top = blockRect.top - wrapperRect.top;
      var left = blockRect.left - wrapperRect.left - 30;

      this._dragHandle.style.top = top + "px";
      this._dragHandle.style.left = Math.max(0, left) + "px";
      this._dragHandle.style.display = "flex";
    },

    _createDropIndicator: function () {
      if (this._dragIndicator) this._dragIndicator.remove();
      var indicator = document.createElement("div");
      indicator.className = "leaf-drop-indicator";
      indicator.style.display = "none";
      this._visualWrapper.appendChild(indicator);
      this._dragIndicator = indicator;
    },

    _findDropTarget: function (clientY) {
      var children = this._visualEl.childNodes;
      var blocks = [];

      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (child.nodeType !== Node.ELEMENT_NODE) continue;
        if (this._isBlockTag(child)) {
          blocks.push(child);
        }
      }

      if (blocks.length === 0) return null;

      var best = null;
      var bestDist = Infinity;

      for (var j = 0; j < blocks.length; j++) {
        var block = blocks[j];
        // Skip the block being dragged
        if (block === this._dragSourceBlock) continue;

        var rect = block.getBoundingClientRect();

        var distTop = Math.abs(clientY - rect.top);
        if (distTop < bestDist) {
          bestDist = distTop;
          best = { element: block, position: "before" };
        }

        var distBottom = Math.abs(clientY - rect.bottom);
        if (distBottom < bestDist) {
          bestDist = distBottom;
          best = { element: block, position: "after" };
        }
      }

      // Edge: above first non-source block
      for (var k = 0; k < blocks.length; k++) {
        if (blocks[k] !== this._dragSourceBlock) {
          var firstRect = blocks[k].getBoundingClientRect();
          if (clientY < firstRect.top) {
            return { element: blocks[k], position: "before" };
          }
          break;
        }
      }

      // Edge: below last non-source block
      for (var l = blocks.length - 1; l >= 0; l--) {
        if (blocks[l] !== this._dragSourceBlock) {
          var lastRect = blocks[l].getBoundingClientRect();
          if (clientY > lastRect.bottom) {
            return { element: blocks[l], position: "after" };
          }
          break;
        }
      }

      return best;
    },

    _positionDropIndicator: function (target) {
      if (!this._dragIndicator || !target) return;

      var wrapperRect = this._visualWrapper.getBoundingClientRect();
      var blockRect = target.element.getBoundingClientRect();
      var y;

      if (target.position === "before") {
        y = blockRect.top - wrapperRect.top - 2;
      } else {
        y = blockRect.bottom - wrapperRect.top + 1;
      }

      y = Math.max(0, Math.min(y, this._visualWrapper.offsetHeight));

      this._dragIndicator.style.top = y + "px";
      this._dragIndicator.style.display = "block";
    },

    _cleanupDrag: function () {
      var movedBlock = this._dragSourceBlock;
      if (movedBlock) {
        movedBlock.classList.remove("leaf-dragging");
        this._dragSourceBlock = null;
      }
      if (this._dragIndicator) {
        this._dragIndicator.remove();
        this._dragIndicator = null;
      }
      this._dragDropTarget = null;

      // Re-show handle on the block that was just moved
      if (movedBlock && movedBlock.parentNode === this._visualEl) {
        this._dragHandleBlock = movedBlock;
        this._positionDragHandle(movedBlock);
      } else {
        this._dragHandleBlock = null;
        if (this._dragHandle) {
          this._dragHandle.style.display = "none";
        }
      }
    },

    _dismissImagePopover: function (skipPush) {
      // Remove selection class
      if (this._imagePopoverTarget) {
        this._imagePopoverTarget.classList.remove("leaf-img-selected");
      }
      // Remove resize handles
      if (this._resizeHandles) {
        this._resizeHandles.forEach(function (h) { h.remove(); });
        this._resizeHandles = null;
      }
      // Remove popover
      if (this._imagePopoverEl) {
        this._imagePopoverEl.remove();
        this._imagePopoverEl = null;
      }
      if (this._imagePopoverTarget) {
        this._imagePopoverTarget = null;
        if (!skipPush) this._debouncedPushVisualChange();
      }
    },

    // -- Commands from parent --

    _handleCommand: function (payload) {
      switch (payload.action) {
        case "insert_image":
          if (this._visualEl && payload.url) {
            this._visualEl.focus();
            var imgHtml =
              '<img src="' +
              payload.url +
              '" alt="' +
              (payload.alt || "").replace(/"/g, "&quot;") +
              '" draggable="true" />';
            document.execCommand("insertHTML", false, imgHtml);
            this._debouncedPushVisualChange();
          }
          break;

        case "set_content":
          break;

        case "set_mode":
          if (payload.mode && payload.mode !== this._mode) {
            var tab = this.el.querySelector(
              '[data-mode-tab="' + payload.mode + '"]'
            );
            if (tab) tab.click();
          }
          break;
      }
    },
  };
})();
