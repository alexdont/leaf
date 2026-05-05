# Changelog

## 0.2.13

- Add **hybrid mode** — Obsidian-style live preview that renders formatting inline (bold, italic, strike, code, spoiler, headings, horizontal rule, ordered/unordered lists) while keeping the source markers editable. Markers (`**`, `*`, `~~`, `||`, `` ` ``, `# `…`###### `) appear as faded characters when the cursor is inside their wrapper and fade out as soon as the cursor leaves; arrowing into a wrapper from either side reveals them again. Hybrid is now the first tab in the mode switcher.
- Hybrid auto-format as you type: `**word**`, `*word*`, `~~word~~`, `||word||`, `` `word` ``, and `***word***` wrap on the closing delimiter; `# ` through `###### ` retag the current paragraph as a heading and live-retag when the user adds or removes leading `#`s; `---` on its own line becomes a real `<hr>`; `- ` / `* ` / `+ ` becomes a `<ul>`; `1. ` (or any `\d+. `) becomes an `<ol>` (with `start="N"` when N ≠ 1). Consecutive list paragraphs merge into one wrapper rather than producing one wrapper per item.
- Hybrid horizontal rule is cursor-aware: clicking the rule, or arrowing onto it from above / below, swaps it for an editable `<p data-leaf-hr-source>---</p>` so the dashes can be adjusted or deleted; moving the cursor away renders the rule again. Arrow detection uses bounding-rect line measurement so it fires from the first/last visual line of any block (empty, multi-line, or with a trailing `<br>` filler), not just from an empty paragraph.
- Hybrid handles nested formatting (`***bold-italic***`, `~~**within strike**~~`, etc.) by decorating the full chain of ancestors at once, deferring auto-format inside an unclosed outer delimiter, then recursively wrapping the inner pattern when the outer closes. Editing or deleting a delimiter span unwraps the formatting back to plain text.
- Hybrid keeps typing past the closing delimiter working reliably across browsers — the keystroke is intercepted in `keydown` and inserted outside the wrapper as a sibling, even when Chrome's caret affinity would otherwise pull the cursor back inside. Typing inside an already-formatted paragraph now lands at the cursor position instead of being silently redirected to the end of the line.
- After hybrid auto-formats a wrapper, the caret rests *just past* the closing delimiter (`**bold**|`, not `**bold|**`) while still anchored inside the wrapper so the markers stay visible without needing a click. Decoration markers also appear immediately for second / third / nested wrappers in the same paragraph (previously a click-in was needed).
- Stop the hybrid-only `**` / `*` / `~~` / `# ` decoration markers from leaking into pure visual mode: the deferred toolbar refresh and the heading-decoration listener are now mode-gated, and switching from hybrid to visual strips every existing decoration span (and the cursor-anchoring zero-width spaces heading decoration leaves behind) from the contenteditable.
- Replace the visual-mode HR toolbar handler. `document.execCommand("insertHorizontalRule")` produced inconsistent DOM that didn't round-trip through `htmlToMarkdown`, so the rule vanished on the next re-render and never appeared in markdown mode. The handler now builds the `<hr>` and trailing `<p>` manually (same shape hybrid mode uses), and the duplicate `<hr>` CSS that the JS hook was injecting on top of the inline `<style>` rule is gone — the line renders once, vertically centered inside an 18px hover-friendly hit area.
- Center the drag handle against blocks shorter than the handle itself (in particular hybrid-mode `<hr>`), so the grab icon aligns with the rule's line instead of hovering above the block.
- Fix `markdown → hybrid` and `html → hybrid` mode switches losing the latest edits. `_syncModes` only matched `to === "visual"` when copying content out of the markdown / html textareas, so switching to hybrid left the visual contenteditable showing its previous DOM. Both branches now fire for hybrid too (hybrid reuses the same contenteditable as visual).
- Wire hybrid mode into the footer word / char counter. Counts read 0 / 0 in hybrid before because `_updateCounts` had no branch for it; the new branch reads the contenteditable's text after stripping decoration spans and ZWSPs, so the numbers track user-perceived content and don't jitter when the cursor moves in / out of formatted runs.

## 0.2.12

- Add a vertical resize grip to the visual editor's bottom-right corner so users can drag to grow or shrink the editing area, mirroring the native grip the markdown and html textareas already had. Per-mode resize state (each mode keeps its own height — resizing in visual doesn't change markdown's height and vice versa).
- Double-click the resize grip to auto-fit the editor height to its content. Works for visual, markdown, and html modes. The auto-fit clamps to the configured `:height` as a floor — shorter content still respects the minimum.
- Show a small tooltip ("Drag to resize · Double-click to fit content") when the mouse hovers the resize-grip area, so the double-click gesture is discoverable.
- Fix the bold toolbar button lighting up for plain heading text. `document.queryCommandState("bold")` returns true for any text whose computed `font-weight` is bold, and the editor's own CSS sets `font-weight: 700` on `h1`–`h4`, so a heading without an explicit `<b>`/`<strong>` was misreported as bold. The button now probes for an actual `<b>`/`<strong>` ancestor; explicit bold inside a heading still lights up correctly.
- Add inline spoilers (Discord-style `||hidden text||` markdown) with a Spoiler entry in the More-formatting dropdown. Renders as a censored block (dark background, hidden text) anywhere on the page; click anywhere on the page to reveal. Inside the editor itself the spoiler text is always shown (with a subtle background hint) so writers can see what they're typing.
- Quality-of-life cursor escapes for any inline formatting (`<b>`, `<strong>`, `<i>`, `<em>`, `<s>`, `<del>`, `<code>`, `<u>`, `<sub>`, `<sup>`, `<mark>`, `<a>`, and the spoiler span). Pressing Enter inside any of them breaks out into a fresh paragraph instead of carrying the formatting into the new `<p>`. ArrowLeft at the start or ArrowRight at the end exits the wrapper on a single press; if there's no content on the target side, a non-breaking space is inserted so the cursor has a typeable home.
- Preserve the contenteditable's selection when the user miss-clicks anywhere on the editor's chrome (toolbar gaps, dividers, mode tabs, footer, border, background). `mousedown` is intercepted on the editor wrapper and `preventDefault` keeps focus in the contenteditable; clicks still register so buttons and dropdown triggers behave normally. Clicks on form controls and inside the contenteditable itself are unaffected.
- Make the main image toolbar button fall back to the URL dialog when the consumer hasn't configured an `upload_handler`. The wrapper's `data-has-upload` attribute now correctly reflects whether `upload_handler` is set (it previously misreported truthy whenever `:image` was in the toolbar list). Result: with `:image` in the toolbar but no upload handler, clicking the main image button opens the URL dialog directly instead of silently no-opping.
- Stop the LiveView from crashing on `media_ui_opened` / `media_ui_closed` events that the image-URL dialog (and other media popovers) push. Added no-op handlers; the events are kept on the wire so future server-side reactions to media UI being active can hook in without breaking existing consumers.
- Align toolbar icons on a consistent vertical centerline. SVG icons no longer drift from inline-baseline (`svg { display: block }`), text-glyph buttons (B/I/S/H) get a tighter `line-height: 1`, and the dropdown wrappers for heading, more-formatting, table, and more-inserts now use `inline-flex` so their buttons sit at the same height as direct flex-child buttons instead of being pushed up by the wrapper's line-height. Rules ship in the inline `<style>` block emitted server-side so the alignment is correct on first paint, not just after `mounted()` runs.
- Force Shift+Enter to always insert a soft break (`<br>`) inside the current block. Some browsers — notably Chromium contenteditables that have `defaultParagraphSeparator` set to `"p"` — otherwise treat Shift+Enter the same as plain Enter and start a new `<p>`. The editor now intercepts the key and inserts a `<br>` explicitly, so a single Shift+Enter always continues the current paragraph on a new line and any following `<p>` stays separate.
- Preserve `<br>` soft breaks across visual↔markdown↔html round-trips. Earmark's `breaks: true` HTML output puts a literal `\n` after every `<br>` as pretty-print whitespace, which `htmlToMarkdown` was reading and combining with the `<br>`'s own `\n` into `\n\n` — a markdown paragraph break — causing a single paragraph with internal soft breaks to split into multiple paragraphs after a round-trip. The walker now strips leading newlines from text nodes that follow a `<br>`. Same root cause for the cursor-visibility filler `<br>` that the Shift+Enter handler appends at end of block — it's now marked `data-leaf-filler` and skipped by the markdown walker so a Shift+Enter at end of paragraph doesn't get serialized as a paragraph break.

## 0.2.11

- Treat single newlines in markdown as line breaks when rendering to HTML for visual mode (`breaks: true` passed to Earmark). Content like emoji-prefixed lists or any line-by-line text without blank lines now renders line-by-line in visual mode, matching how the markdown source visually appears in markdown mode and how editors like GitHub, Slack, and Notion handle the same input. Round-trips through visual→markdown still preserve the original `\n`-separated source.

## 0.2.10

- Fix the editor expanding horizontally on mount and stealing space from sibling flex items. The outer wrapper and the toolbar now have `min-width: 0` so the editor's intrinsic min-content width can no longer push past its parent's allocated width. Pages with a `flex-[2] / flex-1` split (or similar) no longer redistribute when the editor finishes mounting.

## 0.2.9

- Loading placeholder now picks a random label per page load by default (`loading_preset` defaults to `:random`, drawing from the bundled set of `:unpuzzling`, `:brewing`, `:polishing`, `:composing`, `:crafting`, `:tidying`). Use `loading_preset={:default}` for the plain "Loading…" label, or `loading_text="…"` to fully customize.
- Fix layout jump on loading→ready: the toolbar, mode tabs, border wrapper, and footer now render as a real skeleton during loading, so the page no longer shifts when the editor finishes mounting.
- Pin `data-leaf-mount-state` to `"ready"` in the JS hook's `updated()` callback so a parent re-render can't briefly flicker the editor back through the loading state.

## 0.2.8

- Add a styled loading placeholder shown until the editor JS mounts, replacing the brief flash of unstyled content on cold page loads. Configurable via two new `leaf_editor/1` attrs:
  - `loading_preset` (`:default | :unpuzzling | :brewing | :polishing | :composing | :crafting | :tidying`) — pick a bundled label
  - `loading_text` — fully custom string, wins over the preset

## 0.2.7

- Fix excessive blank lines in markdown output when pressing Enter in visual mode
- Fix mode toggle reverting to visual and in-progress keystrokes being lost while typing in markdown or html mode
- Fix table column widths shifting while typing into cells

## 0.2.6

- Add edit image URL button (pencil icon) to image floating island
- Add simple/advanced toolbar presets for lightweight vs full editing
- Prevent bold toggling inside headings to keep visual-markdown sync
- Fix drag handle jumping to wrong block on large/resized images
- Fix image popover persistence through LiveView re-renders

## 0.2.5

- Add image insert by URL with split button toolbar (upload + by URL options)
- Add inline URL dialog with alt text support for both visual and markdown modes
- Bump sticky toolbar z-index for better stacking with fixed navbars

## 0.2.4

- Remove blue focus outline from contenteditable editor area

## 0.2.3

- Fix footer word/char counts resetting to zero on component re-render

## 0.2.2

- Add `leaf_editor/1` function component wrapper for cleaner `<.leaf_editor />` syntax

## 0.2.1

- Add editor footer with live word and character count

## 0.2.0

- Add drag-and-drop block reordering for images and any block element
- Add drag handles for easier block manipulation with margin hover activation
- Add image resize handles with persistent dimensions through save
- Add table support with insert, add/remove row and column operations
- Add More Inserts dropdown to toolbar for organized insert options
- Add superscript and subscript toolbar buttons
- Add indent/outdent toolbar buttons
- Add emoji picker toolbar button (keeps open for multiple inserts)
- Update toolbar icons to Heroicons
- Fix italic/bold/strikethrough lost on save due to whitespace in markers
- Add sticky toolbar navbar offset detection and morphdom resilience

## 0.1.0

- Initial release
- Dual-mode editor: visual (WYSIWYG) and markdown
- Toolbar with formatting, headings, lists, links, code blocks
- Content syncs between modes via Earmark
- Optional gettext support for i18n
- No npm dependencies — vendored JS bundle
