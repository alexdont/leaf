# Changelog

## 0.2.12

- Add a vertical resize grip to the visual editor's bottom-right corner so users can drag to grow or shrink the editing area, mirroring the native grip the markdown and html textareas already had. Per-mode resize state (each mode keeps its own height — resizing in visual doesn't change markdown's height and vice versa).
- Double-click the resize grip to auto-fit the editor height to its content. Works for visual, markdown, and html modes. The auto-fit clamps to the configured `:height` as a floor — shorter content still respects the minimum.
- Show a small tooltip ("Drag to resize · Double-click to fit content") when the mouse hovers the resize-grip area, so the double-click gesture is discoverable.
- Fix the bold toolbar button lighting up for plain heading text. `document.queryCommandState("bold")` returns true for any text whose computed `font-weight` is bold, and the editor's own CSS sets `font-weight: 700` on `h1`–`h4`, so a heading without an explicit `<b>`/`<strong>` was misreported as bold. The button now probes for an actual `<b>`/`<strong>` ancestor; explicit bold inside a heading still lights up correctly.
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
