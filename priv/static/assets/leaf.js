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

    // Links
    ".content-editor-visual a { color: var(--color-primary, #3b82f6); text-decoration: underline; cursor: text; }",
    ".content-editor-visual a:hover { opacity: 0.8; }",

    // Images
    ".content-editor-visual img {",
    "  max-width: 100%; height: auto; border-radius: 0.5rem; margin: 0.75em 0;",
    "  cursor: default;",
    "}",

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
    return nodeToMarkdown(container).trim();
  }

  function nodeToMarkdown(node) {
    var result = "";
    for (var i = 0; i < node.childNodes.length; i++) {
      result += convertNode(node.childNodes[i]);
    }
    return result;
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
        return "\n";

      case "strong":
      case "b":
        return "**" + inner + "**";

      case "em":
      case "i":
        return "*" + inner + "*";

      case "s":
      case "del":
      case "strike":
        return "~~" + inner + "~~";

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

      this._editorId = this.el.dataset.editorId;
      this._mode = this.el.dataset.mode || "visual";
      this._debounceMs = parseInt(this.el.dataset.debounce || "400", 10);
      this._readonly = this.el.dataset.readonly === "true";
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
      this._setupModeSwitcher();
      this._setupLinkPopover();
      this._registerMarkdownHelpers();
      this._setupMarkdownTextarea();
      this._setupHtmlTextarea();

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
      if (!this._visualEl) return;
      var newReadonly = this.el.dataset.readonly === "true";
      if (newReadonly !== this._readonly) {
        this._readonly = newReadonly;
        this._visualEl.contentEditable = !newReadonly;
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

      this._dismissLinkPopover();
      if (this._onDocClickForPopover) {
        document.removeEventListener("mousedown", this._onDocClickForPopover);
      }

      // Clean up global markdown helper functions
      var gid = this._editorId.replace(/-/g, "_") + "_markdown";
      delete window["markdownFormat_" + gid];
      delete window["markdownLinePrefix_" + gid];
      delete window["markdownLink_" + gid];
      delete window["markdownEditorInsert_" + gid];
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
    },

    _setupMarkdownTextarea: function () {
      var self = this;
      var textarea = this._getMarkdownTextarea();
      if (!textarea) return;

      this._markdownInputHandler = function () {
        self._debouncedPushMarkdownChange(textarea.value);
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
      });
    },

    _getHtmlTextarea: function () {
      return document.getElementById(
        this._editorId + "-html-textarea"
      );
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

    // -- Event handlers --

    _onVisualInput: function () {
      if (this._mode !== "visual") return;
      this._dismissLinkPopover();
      this._debouncedPushVisualChange();
    },

    _onVisualKeydown: function (e) {
      if (this._readonly) return;

      var mod = e.ctrlKey || e.metaKey;

      if (mod && e.key === "b") {
        e.preventDefault();
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

    _execToolbarAction: function (action) {
      if (this._readonly) return;

      if (this._mode === "markdown") {
        this._execMarkdownToolbarAction(action);
        return;
      }

      if (!this._visualEl) return;
      this._visualEl.focus();

      switch (action) {
        case "bold":
          document.execCommand("bold", false, null);
          break;
        case "italic":
          document.execCommand("italic", false, null);
          break;
        case "strike":
          document.execCommand("strikeThrough", false, null);
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
        case "blockquote":
          this._toggleBlockquote();
          break;
        case "codeBlock":
          document.execCommand("formatBlock", false, "pre");
          break;
        case "horizontalRule":
          document.execCommand("insertHorizontalRule", false, null);
          break;
        case "link":
          this._insertLink();
          break;
        case "insert-image":
          this.pushEventTo(this.el, "insert_request", {
            editor_id: this._editorId,
            type: "image",
          });
          break;
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
        case "code": if (fmt) fmt("`", "`"); break;
        case "heading1": if (pfx) pfx("# "); break;
        case "heading2": if (pfx) pfx("## "); break;
        case "heading3": if (pfx) pfx("### "); break;
        case "heading4": if (pfx) pfx("#### "); break;
        case "bulletList": if (pfx) pfx("- "); break;
        case "orderedList": if (pfx) pfx("1. "); break;
        case "blockquote": if (pfx) pfx("> "); break;
        case "codeBlock": if (fmt) fmt("```\n", "\n```"); break;
        case "horizontalRule": if (ins) ins("\n---\n"); break;
        case "link": if (lnk) lnk(); break;
        case "insert-image": this.pushEventTo(this.el, "insert_request", { editor_id: this._editorId, type: "image" }); break;
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
            active = document.queryCommandState("bold");
            break;
          case "italic":
            active = document.queryCommandState("italic");
            break;
          case "strike":
            active = document.queryCommandState("strikeThrough");
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

    // -- Image popover --

    _showImagePopover: function (imgEl) {
      this._dismissImagePopover();
      this._imagePopoverTarget = imgEl;

      var src = imgEl.getAttribute("src") || "";
      var alt = imgEl.getAttribute("alt") || "";
      var self = this;

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

    _dismissImagePopover: function () {
      if (this._imagePopoverEl) {
        this._imagePopoverEl.remove();
        this._imagePopoverEl = null;
        this._imagePopoverTarget = null;
        this._debouncedPushVisualChange();
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
              '" />';
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
