# Changelog

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
