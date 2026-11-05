defmodule Leaf.Styles do
  @moduledoc false
  # The inline CSS each editor emits so it looks right before its JS hook runs.

  # Inline CSS for the loading state. Emitted once per editor at the top of
  # render/1 so it applies on first paint, before the JS hook injects the
  # full editor stylesheet in mounted().
  @doc false
  def loading_state_css(height) do
    """
    [data-leaf-mount-state="loading"] [data-leaf-content] { display: none; }
    [data-leaf-mount-state="ready"] [data-leaf-loading] { display: none; }
    [data-leaf-loading] {
      display: flex; align-items: center; justify-content: center;
      min-height: #{height};
      font: 500 0.875rem/1 ui-sans-serif, system-ui, -apple-system, sans-serif;
      color: #6b7280;
    }
    [data-leaf-loading] span {
      background: linear-gradient(90deg, #9ca3af 0%, #d1d5db 50%, #9ca3af 100%);
      background-size: 200% 100%;
      -webkit-background-clip: text; background-clip: text; color: transparent;
      animation: leaf-loading-shimmer 1.6s ease-in-out infinite;
    }
    @keyframes leaf-loading-shimmer {
      0% { background-position: 100% 50%; }
      100% { background-position: -100% 50%; }
    }

    /* Editor gutter + positioning context — emitted inline so they do not
       depend on the host app's Tailwind build generating the `p-4 pl-10`
       / `relative` utility classes. The block drag handle is positioned
       inside this left gutter; without it the handle overlaps the text
       (e.g. when leaf is embedded in a host whose Tailwind does not scan
       the leaf library files). Mirrors the `overflow-auto p-4 pl-10`
       classes on [data-editor-visual] and `relative` on the wrapper. */
    [data-visual-wrapper] { position: relative; }

    /* Preserved-tag previews. Emitted with the markup that needs them, not
       left to the JS bundle's stylesheet: the bundle is cached by the
       browser separately from the page, and a tab holding an older one
       would draw new markup with none of its styling — a block of bare
       text. The markup and its CSS now always arrive together. */
    /* Component kinds (`tag_previews`): a preserved tag drawn like the */
    /* thing it is. See kind_chip_body in lib/leaf.ex. */
    .content-editor-visual .leaf-atomic-kind-headline > .leaf-kind-headline,
    .content-editor-visual .leaf-atomic-kind-button > .leaf-kind-button,
    .content-editor-visual .leaf-atomic-kind-audio > .leaf-kind-audio { margin-right: 5.5rem; }
    .content-editor-visual .leaf-kind-headline {
      display: block; font-size: 1.9em; font-weight: 800; line-height: 1.15;
      letter-spacing: -0.01em;
    }
    .content-editor-visual .leaf-kind-meta {
      display: block; margin-top: 0.55em;
      font: 400 0.72em/1.4 ui-monospace, SFMono-Regular, monospace;
      color: color-mix(in oklab, var(--color-base-content, #1f2937) 45%, transparent);
    }
    .content-editor-visual .leaf-kind-split { display: flex; gap: 1rem; align-items: stretch; margin-top: 0.6rem; }
    .content-editor-visual .leaf-kind-split-right { flex-direction: row-reverse; }
    .content-editor-visual .leaf-kind-split-media { display: block; flex: 0 0 38%; min-width: 0; }
    .content-editor-visual .leaf-kind-picture {
      display: block; width: 100%; height: 100%; min-height: 7rem; max-height: 12rem;
      object-fit: cover; border-radius: 0.4rem; cursor: default;
    }
    .content-editor-visual .leaf-kind-placeholder {
      display: flex; align-items: center; justify-content: center;
      height: 100%; min-height: 7rem; border-radius: 0.4rem; font-size: 0.85em;
      border: 2px dashed color-mix(in oklab, var(--color-base-content, #1f2937) 25%, transparent);
      color: color-mix(in oklab, var(--color-base-content, #1f2937) 50%, transparent);
    }
    .content-editor-visual .leaf-kind-split-text { display: block; flex: 1; min-width: 0; align-self: center; line-height: 1.5; }
    .content-editor-visual .leaf-kind-button {
      display: inline-block; padding: 0.45em 1.3em; border-radius: 999px; font-weight: 650;
      background: color-mix(in oklab, var(--color-primary, #3b82f6) 16%, transparent);
      color: color-mix(in oklab, var(--color-primary, #3b82f6) 90%, var(--color-base-content, #1f2937));
    }
    .content-editor-visual .leaf-kind-frame {
      display: block; padding: 0.8rem 1rem; border-radius: 0.4rem;
      border: 1px solid color-mix(in oklab, var(--color-base-content, #1f2937) 22%, transparent);
      background: var(--color-base-100, #fff);
    }
    .content-editor-visual .leaf-kind-frame-title { display: block; font-weight: 650; }
    .content-editor-visual .leaf-kind-frame-url {
      display: block; margin-top: 0.15em; word-break: break-all;
      font: 400 0.78em ui-monospace, SFMono-Regular, monospace;
      color: color-mix(in oklab, var(--color-base-content, #1f2937) 55%, transparent);
    }
    .content-editor-visual .leaf-kind-audio {
      display: flex; align-items: center; gap: 0.7rem; padding: 0.55rem 0.8rem; border-radius: 0.5rem;
      background: color-mix(in oklab, var(--color-base-content, #1f2937) 6%, transparent);
    }
    .content-editor-visual .leaf-kind-audio-play {
      display: inline-flex; align-items: center; justify-content: center; flex: 0 0 auto;
      width: 1.7rem; height: 1.7rem; border-radius: 50%; font-size: 0.7em;
      background: var(--color-primary, #3b82f6); color: var(--color-primary-content, #fff);
    }
    .content-editor-visual .leaf-kind-audio-bar {
      display: block; flex: 1; height: 4px; border-radius: 2px; min-width: 2rem;
      background: color-mix(in oklab, var(--color-base-content, #1f2937) 22%, transparent);
    }
    .content-editor-visual .leaf-kind-audio-title { font-size: 0.85em; }
    /* Block children flattened to inline elements (see flatten_block_children */
    /* in lib/leaf.ex): still one per line, but safe inside the chip's <p>. */
    .content-editor-visual .leaf-atomic-h { font-size: 1.05em; font-weight: 650; }
    .content-editor-visual .leaf-atomic-li::before { content: '• '; opacity: 0.6; }
    .content-editor-visual .leaf-atomic-quote {
      display: inline-block; padding-left: 0.7em;
      border-left: 3px solid color-mix(in oklab, var(--color-base-content, #1f2937) 25%, transparent);
    }
    .content-editor-visual .leaf-atomic-pre {
      font: 400 0.85em ui-monospace, SFMono-Regular, monospace; white-space: pre-wrap;
    }
    /* Tags nested in a tag (a Gallery's images): a row of thumbnails, or */
    /* small labelled chiplets where there is no picture to draw. */
    .content-editor-visual .leaf-atomic-children {
      display: flex; flex-wrap: wrap; align-items: center; gap: 0.4rem; margin-top: 0.55em;
    }
    .content-editor-visual .leaf-atomic-thumb {
      display: block; width: 4.5rem; height: 3.4rem; object-fit: cover;
      border-radius: 0.3rem; cursor: default;
      background: color-mix(in oklab, var(--color-base-content, #1f2937) 6%, transparent);
    }
    .content-editor-visual .leaf-atomic-chiplet {
      display: inline-block; padding: 0.15em 0.55em; border-radius: 0.3rem;
      font-size: 0.78em;
      border: 1px dashed color-mix(in oklab, var(--color-base-content, #1f2937) 30%, transparent);
      color: color-mix(in oklab, var(--color-base-content, #1f2937) 65%, transparent);
    }
    .content-editor-visual {
      box-sizing: border-box;
      overflow: auto;
      padding: 1rem;
      padding-left: 2.5rem;
    }

    /* Toolbar alignment — emitted inline so the icon row sits on a single
       centerline at first paint, before the JS hook injects the full
       editor stylesheet. Without this the toolbar is briefly jagged. */
    [data-visual-toolbar] svg { display: block; }
    [data-visual-toolbar] button { line-height: 1; }
    /* The letter buttons (H B I S </>) are text, not icons. At the 11px
       size of a `btn-xs` label they read smaller than the 14px icons beside
       them (undo, lists, link…), so they take the icons' size and sit
       centered in the same box. */
    [data-visual-toolbar] button[data-toolbar-action="bold"],
    [data-visual-toolbar] button[data-toolbar-action="italic"],
    [data-visual-toolbar] button[data-toolbar-action="strike"],
    [data-visual-toolbar] button[data-heading-trigger] {
      font-size: 13px;
      justify-content: center;
      align-items: center;
    }
    [data-visual-toolbar] button[data-mode-tab="html"] {
      font-size: 12px;
      justify-content: center;
      align-items: center;
    }
    /* The overflow dots and the Markdown mark are drawn small inside their
       box; sized up so their ink matches the 14px icons. */
    [data-visual-toolbar] [data-inline-more-trigger] svg,
    [data-visual-toolbar] [data-insert-more-trigger] svg {
      width: 18px;
      height: 18px;
    }
    [data-visual-toolbar] button[data-mode-tab="markdown"] svg {
      width: 20px;
      height: 9px;
    }
    [data-mobile-toolbar] svg { display: block; }
    [data-mobile-toolbar] button { line-height: 1; }
    [data-visual-toolbar] [data-heading-dropdown],
    [data-visual-toolbar] [data-inline-more-dropdown],
    [data-visual-toolbar] [data-table-dropdown],
    [data-visual-toolbar] [data-insert-more-dropdown] {
      display: inline-flex;
      align-items: center;
    }
    [data-mode-switcher-compact] > summary {
      list-style: none;
    }
    [data-mode-switcher-compact] > summary::-webkit-details-marker {
      display: none;
    }
    [data-mobile-tools-menu] > summary,
    [data-mobile-options-menu] > summary {
      list-style: none;
    }
    [data-mobile-tools-menu] > summary::-webkit-details-marker,
    [data-mobile-options-menu] > summary::-webkit-details-marker {
      display: none;
    }
    [data-visual-toolbar][data-compact-modes="true"] [data-mode-switcher="inline"] {
      display: none;
    }
    [data-visual-toolbar][data-compact-modes="true"] [data-mode-switcher-compact] {
      display: inline-flex;
      margin-left: auto;
    }
    [data-visual-toolbar][data-compact-modes="true"] [data-toolbar-section="fullscreen"] {
      display: none;
    }
    [data-visual-toolbar][data-compact-modes="true"] > .flex-1 {
      display: none;
    }
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-toolbar-overflow="remove-format"],
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-toolbar-divider="remove-format"] {
      display: none !important;
    }
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-compact-overflow="remove-format"] {
      display: list-item !important;
    }
    /* Extra tools (host toolbar_extra + export) collapse into the compact
       menu the moment compact mode engages — same as remove-format — so
       they never spill onto a second row.

       `toolbar_extra` entries marked `collapse: false` land in
       [data-toolbar-extra-pinned] instead, which carries no
       data-toolbar-overflow key and so is never matched by any of the
       collapse rules below. They are the host's primary actions — the
       components its documents are built from — and burying those under
       "More" makes them barely more discoverable than typing the tag by
       hand, which is the problem they existed to solve. */
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-toolbar-overflow="extra"],
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-toolbar-divider="extra"],
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-toolbar-overflow="export"],
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-toolbar-divider="export"] {
      display: none !important;
    }
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-compact-overflow="extra"],
    [data-visual-toolbar][data-compact-modes="true"][data-toolbar-preset="advanced"] [data-compact-overflow="export"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="remove-format"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-divider="remove-format"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="insert-more"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="remove-format"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-title"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-blockquote"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-codeblock"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-hr"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="1"], [data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-more-extra"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="insert-table"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="2"], [data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-table"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="insert-video"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="list-outdent"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-video"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="lists-title"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="3"], [data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="list-outdent"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="insert-image"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="4"], [data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-image"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="list-indent"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="insert-emoji"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="list-indent"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="5"], [data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-emoji"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="list-ordered"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="insert-link"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-divider="insert"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="list-ordered"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="6"], [data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="insert-link"] {
      display: list-item !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-overflow="list-bullet"],
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-toolbar-divider="lists"] {
      display: none !important;
    }
    [data-visual-toolbar][data-toolbar-preset="advanced"]:is([data-toolbar-overflow-level="7"], [data-toolbar-overflow-level="8"], [data-toolbar-overflow-level="9"], [data-toolbar-overflow-level="10"]) [data-compact-overflow="list-bullet"] {
      display: list-item !important;
    }

    /* Touch-specific tweaks. These are about finger ergonomics
       regardless of viewport size — image resize handles, hover-only
       drag handle. (Size-based responsive layout is below in
       `@container`.) */
    @media (pointer: coarse) {
      .leaf-resize-handle {
        width: 24px !important;
        height: 24px !important;
      }
      .leaf-drag-handle {
        display: none !important;
      }
    }

    /* Responsive toolbar — gates on the EDITOR'S OWN width (container
       query), not the viewport, so the toolbar reacts the same whether
       the user is on a phone, a narrow laptop split, or a narrow embed
       inside a wider page. Below ~640px the toolbar stays stationary
       and wraps into compact groups so every section is visible without
       horizontal discovery. Container queries: Chrome 105+, Safari 16+,
       Firefox 110+. */
    @container leaf-editor (max-width: 640px) {
      [data-visual-toolbar] {
        gap: 0.25rem 0.375rem;
        padding: 0.375rem;
      }

      [data-visual-toolbar] > .flex-1 {
        display: none;
      }

      [data-visual-toolbar] .mr-2 {
        margin-right: 0 !important;
      }

      [data-visual-toolbar] [data-visual-toolbar-buttons] > .flex {
        display: contents;
      }

      [data-visual-toolbar] [data-mode-switcher="inline"] {
        display: none;
      }

      [data-visual-toolbar] [data-mode-switcher-compact] {
        display: inline-flex;
        margin-left: auto;
      }

      [data-visual-toolbar] [data-toolbar-section="fullscreen"] {
        display: none;
      }

      [data-visual-toolbar] button {
        min-width: 1.625rem;
        min-height: 1.625rem;
        height: 1.625rem;
        padding-left: 0.25rem;
        padding-right: 0.25rem;
      }

      [data-visual-toolbar] svg {
        width: 0.875rem;
        height: 0.875rem;
      }

      [data-visual-toolbar] [data-mode-switcher],
      [data-visual-toolbar] > .flex.items-center {
        flex-wrap: nowrap;
        gap: 0.125rem;
      }
    }

    @container leaf-editor (max-width: 660px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="remove-format"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-divider="remove-format"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="remove-format"] {
        display: list-item !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="insert-more"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-title"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-blockquote"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-codeblock"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-hr"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-more-extra"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 630px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="insert-table"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-table"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 600px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="insert-video"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-video"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 570px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="insert-image"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-image"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 540px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="insert-emoji"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-emoji"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 510px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="insert-link"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-divider="insert"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="insert-link"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 580px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="list-outdent"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="lists-title"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="list-outdent"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 550px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="list-indent"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="list-indent"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 520px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="list-ordered"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="list-ordered"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 490px) {
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-overflow="list-bullet"],
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-toolbar-divider="lists"] {
        display: none !important;
      }
      [data-visual-toolbar][data-toolbar-preset="advanced"] [data-compact-overflow="list-bullet"] {
        display: list-item !important;
      }
    }

    @container leaf-editor (max-width: 480px) {
      [data-visual-toolbar] {
        display: none !important;
      }

      [data-mobile-toolbar] {
        display: flex;
      }

      [data-mobile-toolbar] button,
      [data-mobile-toolbar] summary {
        min-width: 2.25rem;
        min-height: 2.25rem;
        height: 2.25rem;
      }

      [data-mobile-toolbar] ul button {
        min-height: 2rem;
        height: auto;
      }
    }

    /* Hybrid mode (Obsidian-style live preview): per-char contenteditable=false
       spans inserted by the JS hook around markdown delimiters when the
       cursor is inside a formatted element. Faded so they look like a
       hint and never inherit the parent's bold/italic/strike styling. */
    .leaf-syntax-decoration {
      opacity: 0.55;
      font-weight: normal;
      font-style: normal;
      text-decoration: none;
    }

    /* Widen the hit area for hybrid-mode `<hr>` rules so the click
       handler can reliably swap them to an editable `<p>---</p>`, and
       render the line via a centered `::before` so it sits in the
       middle of the drag-handle's hover block (the default `<hr>`
       border-line otherwise hugs the top of its padding box). */
    .content-editor-visual hr {
      position: relative;
      border: 0;
      height: 18px;
      margin: 0.25em 0;
      cursor: pointer;
      background: transparent;
    }
    .content-editor-visual hr::before {
      content: "";
      position: absolute;
      top: 50%;
      left: 0;
      right: 0;
      border-top: 1px solid currentColor;
      opacity: 0.3;
      transform: translateY(-50%);
    }

    /* Hybrid source mode: a block whose cursor is inside it gets swapped
       for a `<p data-leaf-source="origTag">` carrying its markdown source
       as literal text. Markers (`#`, `**`, `*`, etc.) are wrapped in
       `<span class="leaf-source-marker">` so they can be faded; the
       block itself inherits the visual weight of its original tag so a
       heading still looks like a heading while you're editing the
       source. */
    .content-editor-visual [data-leaf-source] {
      /* Inline-block keeps the source block on a single line for inline
         tags but still flows like a paragraph in the editor. */
    }
    /* A list item in source mode mirrors how inline markers reveal: by
       default it looks rendered — the natural bullet / number (or, for a
       task, the checkbox) shows and the literal `- ` / `N. ` / `- [ ] `
       marker is hidden. The marker reveals — and the bullet / checkbox
       hides — only while the cursor is on it (the li carries
       `.leaf-marker-active`, toggled by `_refreshSourceBlock`). So the row
       reads as formatted until you cursor onto the marker, just like
       `**bold**`. */
    .content-editor-visual li[data-leaf-source="li"] > .leaf-list-marker {
      display: none;
    }
    .content-editor-visual li[data-leaf-source="li"].leaf-marker-active {
      /* Hide the bullet / number and seat the revealed `- ` in the marker
         gutter (negative text-indent) so it lines up with sibling items'
         bullets. Only the first line shifts (hanging indent). */
      list-style: none;
      text-indent: -1.2em;
    }
    .content-editor-visual li[data-leaf-source="li"].leaf-marker-active > .leaf-list-marker {
      display: inline;
      opacity: 0.4;
    }
    /* Task items: the checkbox already sits in the marker gutter via the
       `.leaf-task` margin, so the revealed `- [ ] ` needs no text-indent;
       hide the checkbox box while the marker is showing. */
    .content-editor-visual li[data-leaf-source="li"].leaf-task.leaf-marker-active {
      text-indent: 0;
    }
    .content-editor-visual li[data-leaf-source="li"].leaf-task.leaf-marker-active > .leaf-task-box {
      display: none;
    }
    /* Marker deleted (no valid `- ` / `N. ` left): hide the bullet/number
       so the broken formatting is obvious immediately — the item breaks
       out to a `<p>` once the cursor leaves the line. */
    .content-editor-visual li[data-leaf-source="li"].leaf-marker-broken {
      list-style: none;
    }
    .content-editor-visual [data-leaf-source="h1"] {
      font-size: 2em;
      font-weight: 700;
      line-height: 1.2;
      margin: 0.67em 0;
    }
    .content-editor-visual [data-leaf-source="h2"] {
      font-size: 1.5em;
      font-weight: 700;
      line-height: 1.25;
      margin: 0.83em 0;
    }
    .content-editor-visual [data-leaf-source="h3"] {
      font-size: 1.25em;
      font-weight: 700;
      line-height: 1.3;
      margin: 1em 0;
    }
    .content-editor-visual [data-leaf-source="h4"] {
      font-size: 1em;
      font-weight: 700;
      line-height: 1.35;
      margin: 1.33em 0;
    }
    .content-editor-visual [data-leaf-source="h5"] {
      font-size: 0.85em;
      font-weight: 700;
      margin: 1.67em 0;
    }
    .content-editor-visual [data-leaf-source="h6"] {
      font-size: 0.75em;
      font-weight: 700;
      margin: 2.33em 0;
    }
    /* Anchor styling — Tailwind preflight resets `<a>` to inherit
       color and text-decoration, so without this rule a rendered link
       inside the editor would look identical to surrounding plain
       text. Use the framework's primary color via `currentColor` so
       the link still adapts to the active theme. */
    .content-editor-visual a {
      color: #2563eb;
      text-decoration: underline;
      cursor: pointer;
    }
    /* Markers come in two flavors:
       1. Block prefix (heading `# `, etc.) — direct child of the source
          block. Always visible while the block is in source mode, just
          faded so the user can see what they typed.
       2. Inline markers (`**`, `*`, `~~`, `||`, `` ` ``) — children of
          the formatted element (`<strong>`, `<em>`, `<del>`, `<code>`,
          `.leaf-spoiler`). Hidden by default so an inactive inline
          match looks exactly like its rendered form; revealed (still
          faded) when the wrapper carries `.leaf-source-active`, i.e.
          the cursor's inside the match. */
    .content-editor-visual [data-leaf-source] > .leaf-source-marker {
      opacity: 0.4;
      font-weight: inherit;
    }
    .content-editor-visual [data-leaf-source] strong .leaf-source-marker,
    .content-editor-visual [data-leaf-source] em .leaf-source-marker,
    .content-editor-visual [data-leaf-source] del .leaf-source-marker,
    .content-editor-visual [data-leaf-source] s .leaf-source-marker,
    .content-editor-visual [data-leaf-source] code .leaf-source-marker,
    .content-editor-visual [data-leaf-source] a .leaf-source-marker,
    .content-editor-visual [data-leaf-source] .leaf-spoiler .leaf-source-marker {
      display: none;
    }
    .content-editor-visual [data-leaf-source] .leaf-source-active > .leaf-source-marker {
      display: inline;
      opacity: 0.4;
      font-weight: inherit;
    }

    """
  end
end
