defmodule Leaf do
  @moduledoc """
  Dual-mode content editor LiveComponent with visual (WYSIWYG) and markdown modes.

  Visual mode uses a contenteditable div with vanilla JS (no npm dependencies).
  Markdown mode uses a plain textarea with toolbar support.
  Content syncs between modes using MDEx (markdown→HTML) and client-side
  HTML→markdown conversion.

  ## Usage

      import Leaf, only: [leaf_editor: 1]

      <.leaf_editor
        id="my-editor"
        content={@content}
        mode={:visual}
        preset={:advanced}
        toolbar={[:image, :video]}
        placeholder="Write something..."
        readonly={false}
        height="480px"
        debounce={400}
      />

  ## Presets

  - `:advanced` (default) — Full toolbar with all formatting options
  - `:simple` — Compact toolbar for comments/lightweight editing:
    undo/redo, bold, italic, strikethrough, inline code, lists, link, emoji, clear formatting

  ## Messages Sent to Parent

  - `{:leaf_changed, %{editor_id, markdown, html}}` — Content updated
  - `{:leaf_flushed, %{editor_id, ref, markdown, html}}` — Reply to an
    explicit `action: :flush` that carried a `ref` (see "Flushing" below)
  - `{:leaf_insert_request, %{editor_id, type: :image | :video}}` — Insert requested
  - `{:leaf_mode_changed, %{editor_id, mode: :visual | :markdown}}` — Mode switched
  - `{:leaf_suggest, %{editor_id, trigger, query, seq}}` — Inline suggestion
    requested (only when `suggestions` is configured; see below)

  ## Flushing (save before navigate)

  `send_update(Leaf, id: …, action: :flush)` tells the client to push its
  pending keystrokes immediately. On its own that reply is an ordinary
  `{:leaf_changed, …}` — indistinguishable from the debounce firing — so a
  host that needs to *await* the flush (version switch, language switch,
  translation enqueue) passes a correlation `ref`:

      send_update(Leaf, id: "content-editor", action: :flush, ref: "save-42")

  The client echoes it back on a dedicated message, after the matching
  `{:leaf_changed, …}`:

      def handle_info({:leaf_flushed, %{ref: "save-42", markdown: md}}, socket) do
        # every keystroke is in; safe to persist and navigate
      end

  `ref` must be JSON-encodable (a string or integer). Without a `ref` no
  `{:leaf_flushed, …}` is sent at all, so hosts written against older
  versions keep their exact behaviour — a `handle_info/2` that does not
  match the new message can never be reached by accident.

  ## Inline Suggestions

  The editor can offer a popup as the writer types a trigger character —
  `#` for tags, `@` for people, `/` for components, `:` for emoji. It knows
  nothing about any of those: it detects a configured trigger, asks the host
  what matches, renders the list and inserts the pick.

      <.leaf_editor
        id="post-content-editor"
        content={@content}
        suggestions={[
          %{
            trigger: "#",
            boundary: :word_start,
            token: ~r/[\\p{L}\\p{N}_-]/u,
            first_char: ~r/\\p{L}/u,
            max_length: 30,
            min_chars: 0,
            debounce: 150,
            max_results: 10,
            allow_create: true,
            insert_suffix: " ",
            label: "Tags"
          }
        ]}
      />

  Every key but `:trigger` is optional. Keys may be atoms or strings, and
  `:token` / `:first_char` take either a `Regex` or a raw character-class
  string.

  | Key | Default | Meaning |
  | --- | --- | --- |
  | `:trigger` | — | Required. The character(s) that open the popup. |
  | `:boundary` | `:word_start` | Where a token may start: `:word_start` (start of input, whitespace or `(`), `:line_start`, `:not_line_start` (like `:word_start`, but never the first character of a line), or `:any`. |
  | `:token` | `~r/[\\p{L}\\p{N}_-]/u` | Characters that continue the token. Typing anything else closes the popup. |
  | `:first_char` | none | Extra constraint on the first character after the trigger. |
  | `:min_chars` | `0` | Query length before the popup opens. `0` opens on the bare trigger. |
  | `:max_length` | unlimited | Longest token that still counts. |
  | `:debounce` | `150` | Milliseconds before the query goes to the host. |
  | `:max_results` | `10` | Rows rendered from the host's reply. |
  | `:allow_create` | `false` | Adds a "Create …" row when nothing matches exactly. |
  | `:keep_trigger` | `true` | Whether the accepted text keeps the trigger. `#` and `@` keep it; a `/` command menu sets `false` so `/im` becomes `<Image />`, not `/<Image />`. |
  | `:insert_suffix` | `" "` | Appended after the accepted value. |
  | `:label` | none | Heading shown above the list. |
  | `:exclude` | `[:code, :link]` | Contexts where the popup must not open. |

  ### The round trip

  A request arrives as a message to the host LiveView, and the reply goes
  back through `send_update/2` — the same shape as every other Leaf command:

      def handle_info({:leaf_suggest, %{editor_id: id, trigger: "#", query: q, seq: seq}}, socket) do
        results =
          Enum.map(Hashtags.suggest(socket.assigns.group, q, limit: 10), fn tag ->
            %{value: tag.name, label: "#" <> tag.name, sublabel: "\#{tag.count} posts", icon: "hero-hashtag"}
          end)

        send_update(Leaf, id: id, action: :suggestions, trigger: "#", query: q, seq: seq, results: results)
        {:noreply, socket}
      end

  Results may also be plain strings (`["elixir", "phoenix"]`). `:icon` is a
  CSS class name (the heroicons convention) and is rendered only when given,
  so an app without that plugin never shows an empty gutter.

  Two rules outrank the shape of any of this:

  - **Stale replies are dropped.** Keystrokes routinely outrun a round trip,
    so echo `trigger`, `query` and `seq` back unchanged — the client matches
    on all three and ignores anything superseded.
  - **Typing is never blocked.** A host that never answers gets a short
    spinner and then the popup closes on its own. A hand-typed `#tag` is
    already valid; this is an enhancement over something that works without
    it.

  ### What the popup will not do

  With `exclude: [:code, :link]` (the default) the popup stays shut inside
  fenced and inline code, inside a markdown link/image destination
  (`[jump](#section)`), and — via the `:word_start` boundary — after a
  non-space character, which covers URL fragments like `/page#section`.
  The checks are client-side approximations: in the visual and hybrid modes
  they ask the DOM for `<code>` / `<pre>` / `<a>` ancestors, in the markdown
  and HTML modes they count delimiters. A stray popup is cosmetic — nothing
  is ever written to the document except by accepting a row.

  One case worth knowing about `#` specifically. In markdown a heading is
  `#` followed by a **space** — `# Notes` is a heading, `#notes` is a
  paragraph containing a tag, and the editor's hybrid preview agrees with
  MDEx on this. But a lone `#` on an otherwise empty line is a valid (empty)
  heading, so with `min_chars: 0` that single keystroke both renders as a
  heading and opens the tag popup. It resolves itself on the next character:
  a letter makes it a tag, a space makes it a heading. Set `min_chars: 1` if
  you would rather the popup never appear in that ambiguous moment, or
  `boundary: :not_line_start` to keep the popup off the first column
  entirely — then `#` opens a heading and `#tag` mid-line opens the popup,
  with no keystroke where both are live.

  ### Hashtag styling

  Configuring a `#` trigger also tells Leaf that `#` means "tag" in this
  editor, so hashtags render as tinted, slightly-italic tokens in the
  visual and hybrid surfaces instead of reading as ordinary prose. It is
  purely a decoration — the markdown stays `#tag` and serialization is
  unchanged. An editor with no `#` trigger gets no hashtag styling, so a
  document that uses `#` for issue numbers is left alone.

  ### Interaction

  ↑/↓ move (wrapping), Enter and Tab accept, Escape dismisses. While the
  popup is open Enter neither inserts a newline, nor continues a list, nor
  submits the surrounding form. Clicking a row does not steal focus from the
  editor. The popup is portaled to `<body>`, anchored to the caret, flips
  above it when there is no room below, and never opens mid-IME-composition.

  ### Testing a trigger

  The popup lives entirely on the client, so a LiveView test drives the
  server half directly:

      render_hook(view, "suggest", %{"trigger" => "#", "query" => "eli", "seq" => 1})
      assert_receive {:leaf_suggest, %{trigger: "#", query: "eli", seq: 1}}

  Popup DOM carries stable hooks for browser-level tests: the popup is
  `#\#{editor_id}-suggest`, rows are `[data-leaf-suggest-index]` and carry
  `data-leaf-suggest-value` and `data-leaf-suggest-kind`
  (`"result"` / `"create"`).

  ## Custom component tags (`preserve_tags`)

  > #### Read this before putting component tags through the editor {: .warning}
  >
  > Markdown holding custom tags — `<Hero />`, `<Showcase>…</Showcase>` —
  > **must** declare them in `preserve_tags`. Without it the visual and
  > hybrid surfaces flatten each one into loose paragraphs on the first
  > keystroke, and autosave writes that back over the original. Leaf logs
  > a warning (see below) the first time it sees an undeclared PascalCase
  > tag, but the declaration is what actually protects the content.

      <.leaf_editor
        id="post-content-editor"
        content={@content}
        preserve_tags={["Hero", "Showcase", "Note", "Audio", "EntityForm"]}
      />

  A declared tag is pulled out before the markdown parser runs, rendered
  as an **atomic block** — non-editable, so nothing inside it can be
  corrupted in place — and restored verbatim on the way back out, so the
  source round-trips byte for byte.

  The block reads as a *preview of the component*, not as its source.
  Known attribute names map to typographic roles and are typeset in the
  editor's own prose voice:

  | Role | Attribute names |
  | --- | --- |
  | Eyebrow | `kicker`, `eyebrow`, `overline`, `badge`, `category` |
  | Title | `title`, `heading`, `headline`, `name`, and `label` with no link |
  | Supporting text | `subtitle`, `subheading`, `tagline`, `description`, `summary`, `caption`, `blurb`, `text`, `body`, `alt` |
  | Banner | `image`, `img`, `poster`, `thumbnail`, `cover`, `background`, `avatar`, `photo`, `banner`, and an image-shaped `src` |
  | Call to action | `label`/`cta`/`button` next to `href`/`url`/`link`/`to` |

  Children render as formatted text, so bold and links inside
  `<Header>…</Header>` are visible while you write. Anything with no role
  falls through to a small, faint source line — for those there is nothing
  better to say. A tag with nothing to show collapses to its nameplate.

  This is a convention, not a contract: Leaf has never seen your `<Hero>`,
  so getting it wrong costs nothing beyond an attribute landing on the
  source line. The scale stays close to prose on purpose — a placeholder
  that reads like a document, not an imitation of the published component.

  **Double-click** a block to edit its raw source in place; ⌘/Ctrl+Enter
  or the Save button commits, Escape cancels.

  When `preserve_tags` is missing a tag that the content uses, Leaf emits
  a one-off `Logger.warning` naming it. Disable with:

      config :leaf, warn_unpreserved_tags: false

  ## Security Note

  The deny-list regex sanitization in this component is a UX layer only.
  Consumers must still validate and allow-list content at the persistence boundary.

  ## Denying features

  `deny` removes affordances entirely — the markup is never rendered, and
  the matching client paths refuse to act, so it is one rule rather than a
  default a stray click can talk its way past.

  | Atom | Effect |
  | --- | --- |
  | `:links` | No link button; `<a>`/`[…](…)` stripped from content |
  | `:images` | No image button; `<img>`/`![…](…)` stripped from content |
  | `:video` | No video button |
  | `:visual_mode` | No visual tab, in any switcher |
  | `:hybrid_mode` | No hybrid tab, in any switcher |
  | `:markdown_mode` | No markdown tab, in any switcher |
  | `:html_mode` | No HTML tab, in any switcher |

  A host whose documents are built from custom component tags typically
  wants the markdown surface only — the visual surfaces cannot edit an
  atomic block's source anyway:

      <.leaf_editor id="content-editor" mode={:markdown}
                    deny={[:visual_mode, :hybrid_mode]} … />

  Denying the mode the host also passed as `mode` falls back to the first
  allowed mode in `:hybrid`, `:visual`, `:markdown`, `:html` order.
  Denying *every* mode raises — it is always a mistake. When only one mode
  survives the switcher is hidden rather than rendered as a single dead tab.

  ## Commands from Parent

  Use `send_update/2`:

      send_update(Leaf, id: "my-editor", action: :insert_image, url: "https://...", alt: "description")
      send_update(Leaf, id: "my-editor", action: :set_content, content: "# Hello")
      send_update(Leaf, id: "my-editor", action: :set_mode, mode: :visual)
      send_update(Leaf, id: "my-editor", action: :flush, ref: "save-42")
      send_update(Leaf, id: "my-editor", action: :mark_saved)

  `:set_content` re-baselines the dirty snapshot by default — replacing the
  content programmatically is not a user edit, so an untouched editor still
  reads clean and `protect_navigation` does not prompt. Pass
  `mark_saved: false` to keep the old baseline (i.e. treat the new content
  as unsaved work).

  ## JS Setup

  Add to your app.js:

      import "../../../deps/leaf/priv/static/assets/leaf.js"

      let Hooks = {
        Leaf: window.LeafHooks.Leaf,
        // ... your other hooks
      }

  ### Checking the bundle is present and current

  Leaf does not bundle its own JS into the host — an editor whose hook
  never attaches renders, looks ordinary and does nothing at all. Two
  things guard against losing an afternoon to that:

  - If the hook has not attached shortly after paint, the editor logs a
    console error naming the likely causes. It stays on its loading
    shimmer rather than pretending to be an editor.
  - `window.LeafHooks.version` reports the version of the loaded bundle.
    Compare it against `Leaf.js_version/0` (which equals the `:leaf`
    application version) to catch a **vendored** copy that stayed behind
    after `mix deps.update leaf`:

        if Leaf.js_version() != vendored_version_from_somewhere do
          Logger.warning("Vendored leaf.js is stale")
        end

    The client does the same check itself whenever the server-rendered
    `data-leaf-js-version` disagrees with the loaded bundle, and warns.

  ## Gettext (optional)

  To enable translations, configure a gettext backend:

      config :leaf, :gettext_backend, MyApp.Gettext

  Otherwise, English strings are used as-is.

  Leaf ships its own catalog template at `priv/gettext/leaf.pot` — a
  host's `mix gettext.extract` cannot see msgids living in a dependency's
  source, so copy it in and merge instead of extracting:

      cp deps/leaf/priv/gettext/leaf.pot priv/gettext/leaf.pot
      mix gettext.merge priv/gettext

  Then translate `priv/gettext/<locale>/LC_MESSAGES/leaf.po`. Lookups try
  the `"leaf"` domain first and fall back to the `"default"` domain, so
  hosts that would rather keep every string in `default.po` can append the
  msgids there and skip the extra domain.
  """

  use Phoenix.LiveComponent

  import Phoenix.HTML, only: [raw: 1]

  require Logger

  # Mode preference order. `normalize_mode/2` falls back along this list
  # when the requested mode is denied, so a host that denies its own
  # `mode:` lands somewhere sensible instead of somewhere arbitrary.
  @mode_order [:hybrid, :visual, :markdown, :html]

  @doc """
  The version of the JS bundle this library ships, as a string.

  Equals the `:leaf` application version. Hosts that **vendor**
  `priv/static/assets/leaf.js` into their own asset pipeline (rather than
  importing it from `deps/`) can compare this against
  `window.LeafHooks.version` to catch a copy that stayed behind after
  `mix deps.update leaf` — the editor renders identically either way, so
  a stale bundle is otherwise silent.
  """
  @spec js_version() :: String.t()
  def js_version do
    case :application.get_key(:leaf, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> "unknown"
    end
  end

  @doc """
  Renders a Leaf editor as a function component.

  This is a convenience wrapper around the `Leaf` LiveComponent.
  Import it in your view helpers:

      import Leaf, only: [leaf_editor: 1]

  Then use it in your templates:

      <.leaf_editor id="my-editor" content={@content} />

  All attributes are passed through to the underlying LiveComponent.
  """
  attr(:id, :string, required: true)
  attr(:content, :string, default: "")
  attr(:mode, :atom, default: :hybrid, values: [:visual, :hybrid, :markdown, :html])
  attr(:preset, :atom, default: :advanced, values: [:advanced, :simple])
  attr(:toolbar, :list, default: [])

  attr(:deny, :list,
    default: [],
    doc: """
    Features to remove entirely: `:links`, `:images`, `:video`,
    `:visual_mode`, `:hybrid_mode`, `:markdown_mode`, `:html_mode`. Denied
    modes lose their tab in every switcher and refuse a `:set_mode`
    command. Denying all four modes raises.
    """
  )

  attr(:placeholder, :string, default: "Write something...")
  attr(:readonly, :boolean, default: false)
  attr(:height, :string, default: "480px")
  attr(:min_height, :string, default: nil)
  attr(:max_height, :string, default: nil)
  attr(:debounce, :integer, default: 400)
  attr(:flush_on_blur, :boolean, default: true)
  attr(:emit_events, :boolean, default: false)

  attr(:toolbar_extra, :list,
    default: [],
    doc: """
    Host-defined toolbar buttons. Each entry is a map (atom or string
    keys):

    - `:id` — required; echoed back as `{:leaf_toolbar_action, %{id: id}}`
    - `:label` — text shown on the button
    - `:title` — tooltip / aria-label
    - `:icon` — **rendered as raw markup** so an inline `<svg>` works.
      That makes it trusted HTML: never build it from user-influenced
      input, or you have an XSS. Use `:glyph` for a built-in icon name
      instead when you don't need custom artwork.
    - `:glyph` — name of a bundled icon, used in the overflow menus
    - `:class` — extra classes on the button
    - `:collapse` — `false` pins the button to the main toolbar row
      instead of letting it fold into the "More" menu when the toolbar
      gets narrow. Use it for the actions your documents are actually
      built from; leave it unset for secondary tools.
    """
  )

  attr(:toolbar_layout, :atom, default: :fixed, values: [:fixed, :floating, :both])

  attr(:preserve_tags, :list,
    default: [],
    doc: """
    Custom component tag names (`["Hero", "Showcase"]`) to protect from
    the HTML round-trip. **Required** for any content using such tags —
    see the "Custom component tags" section; without it the visual and
    hybrid surfaces flatten them into loose paragraphs.
    """
  )

  attr(:maxlength, :integer, default: nil)
  attr(:spellcheck, :boolean, default: true)
  attr(:dir, :string, default: "ltr", values: ["ltr", "rtl", "auto"])
  attr(:smart_typography, :boolean, default: false)
  attr(:export, :boolean, default: false)
  attr(:protect_navigation, :boolean, default: false)

  attr(:save_status, :atom,
    default: nil,
    values: [nil, :saved, :saving, :unsaved]
  )

  attr(:suggestions, :list, default: [])

  # Obsidian-style `[[Target]]` links. `%{resolve: true}` turns the decoration
  # on and asks the host to resolve targets; only the host knows which notes
  # exist. Off by default, so a document using `[[…]]` for something else is
  # untouched.
  attr(:wiki_links, :any, default: nil)

  # Multi-user editing. `%{operations: true}` makes the editor emit what
  # CHANGED alongside the snapshot it already sends, which is what a host needs
  # to merge two people's edits. Off by default; a host that only wants the
  # markdown sees exactly the traffic it always did.
  attr(:collaboration, :any, default: nil)
  attr(:gettext_backend, :any, default: nil)
  attr(:upload_handler, :any, default: nil)
  attr(:sync_input_name, :string, default: nil)
  attr(:class, :string, default: nil)

  attr(:script_nonce, :string,
    default: "",
    doc: """
    CSP nonce applied to the inline `<style>` block and to the
    bundle-presence `<script>` (see `:bundle_check`).
    """
  )

  attr(:bundle_check, :boolean,
    default: true,
    doc: """
    Emit the tiny inline `<script>` that logs a console error when the
    Leaf JS hook never attaches — the difference between "the editor
    silently does nothing" and a one-line diagnosis.

    Set `false` for a host whose CSP forbids inline scripts and which
    cannot supply a `script_nonce`; the check is a diagnostic, nothing
    depends on it. Everything else about the editor is unaffected.
    """
  )

  attr(:loading_preset, :atom,
    default: :random,
    values: [
      :default,
      :random,
      :unpuzzling,
      :brewing,
      :polishing,
      :composing,
      :crafting,
      :tidying
    ]
  )

  attr(:loading_text, :string, default: nil)
  attr(:rest, :global)

  def leaf_editor(assigns) do
    ~H"""
    <.live_component module={Leaf} {assigns} />
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:content, fn -> "" end)
     |> assign_new(:preset, fn -> :advanced end)
     |> assign_new(:toolbar, fn -> [] end)
     |> assign_new(:deny, fn -> [] end)
     |> assign_new(:placeholder, fn -> "Write something..." end)
     |> assign_new(:height, fn -> "480px" end)
     |> assign_new(:min_height, fn -> nil end)
     |> assign_new(:max_height, fn -> nil end)
     |> assign_new(:debounce, fn -> 400 end)
     |> assign_new(:flush_on_blur, fn -> true end)
     |> assign_new(:emit_events, fn -> false end)
     |> assign_new(:toolbar_extra, fn -> [] end)
     |> assign_new(:toolbar_layout, fn -> :fixed end)
     |> assign_new(:preserve_tags, fn -> [] end)
     |> assign_new(:maxlength, fn -> nil end)
     |> assign_new(:spellcheck, fn -> true end)
     |> assign_new(:dir, fn -> "ltr" end)
     |> assign_new(:smart_typography, fn -> false end)
     |> assign_new(:export, fn -> false end)
     |> assign_new(:protect_navigation, fn -> false end)
     |> assign_new(:save_status, fn -> nil end)
     |> assign_new(:suggestions, fn -> [] end)
     |> assign_new(:wiki_links, fn -> nil end)
     |> assign_new(:collaboration, fn -> nil end)
     |> assign_new(:gettext_backend, fn -> nil end)
     |> assign_new(:readonly, fn -> false end)
     |> assign_new(:upload_handler, fn -> nil end)
     |> assign_new(:sync_input_name, fn -> nil end)
     |> assign_new(:loading_preset, fn -> :random end)
     |> assign_new(:loading_text, fn -> nil end)
     |> assign_new(:class, fn -> nil end)
     |> assign_new(:script_nonce, fn -> "" end)
     |> assign_new(:bundle_check, fn -> true end)}
  end

  @impl true
  def update(%{action: :insert_image, url: url} = assigns, socket) do
    alt = Map.get(assigns, :alt, "")

    {:ok,
     push_event(socket, "leaf-command:#{socket.assigns.id}", %{
       action: "insert_image",
       url: url,
       alt: alt
     })}
  end

  # Replacing the content programmatically is not a user edit, so the
  # dirty snapshot is re-baselined alongside it — otherwise loading a
  # different version (or a collaborative sync) leaves `protect_navigation`
  # accusing the writer of unsaved work they never did. `mark_saved: false`
  # opts out, for the rare case where the new content really is a draft.
  def update(%{action: :set_content, content: content} = assigns, socket) do
    deny = Map.get(socket.assigns, :deny, [])
    sanitized_markdown = sanitize_markdown(content, deny)

    html =
      sanitized_markdown
      |> markdown_to_html(render_opts(socket))
      |> sanitize_html(deny)

    {:ok,
     socket
     |> assign(:content, sanitized_markdown)
     |> assign(:visual_html, html)
     |> push_event("leaf-command:#{socket.assigns.id}", %{
       action: "set_content",
       content: sanitized_markdown,
       html: html,
       mark_saved: Map.get(assigns, :mark_saved, true) != false
     })}
  end

  # A denied mode is ignored outright rather than redirected: the deny list
  # is one rule, not a default the host can talk its way past. (The client
  # resolves `[data-mode-tab="…"]` to perform the switch, and that button
  # does not exist for a denied mode, so it degrades quietly there too.)
  def update(%{action: :set_mode, mode: mode}, socket)
      when mode in [:visual, :hybrid, :markdown, :html] do
    deny = Map.get(socket.assigns, :deny, [])

    if mode_denied?(mode, deny) do
      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(:mode, mode)
       |> push_event("leaf-command:#{socket.assigns.id}", %{
         action: "set_mode",
         mode: to_string(mode)
       })}
    end
  end

  def update(%{action: :insert_markdown} = assigns, socket) do
    text = Map.get(assigns, :text, "")

    {:ok,
     push_event(socket, "leaf-command:#{socket.assigns.id}", %{
       action: "insert_markdown",
       text: text
     })}
  end

  # Reply to a `{:leaf_suggest, …}` request. `trigger`, `query` and `seq` are
  # echoed straight back so the client can drop replies that a later keystroke
  # already superseded — keystrokes routinely outrun a server round trip.
  def update(%{action: :suggestions} = assigns, socket) do
    {:ok,
     push_event(socket, "leaf-suggestions:#{socket.assigns.id}", %{
       trigger: to_string(Map.get(assigns, :trigger, "")),
       query: to_string(Map.get(assigns, :query, "")),
       seq: Map.get(assigns, :seq),
       results: normalize_suggestion_results(Map.get(assigns, :results, []))
     })}
  end

  # Reply to a `{:leaf_resolve_links, …}` request. `seq` is echoed back so the
  # client can drop an answer a later edit already superseded — the same guard
  # the suggestion round trip uses, and for the same reason: typing routinely
  # outruns a server round trip.
  def update(%{action: :link_targets} = assigns, socket) do
    {:ok,
     push_event(socket, "leaf-link-targets:#{socket.assigns.id}", %{
       seq: Map.get(assigns, :seq),
       targets: normalize_link_targets(Map.get(assigns, :targets, %{}))
     })}
  end

  # A bare flush produces an ordinary `{:leaf_changed, …}` and nothing
  # else — the historical behaviour. Passing `ref:` opts into a second,
  # identifiable `{:leaf_flushed, %{ref: …}}` so a host can *await* the
  # flush (save-before-navigate) instead of guessing which `:leaf_changed`
  # was the answer. The ref is echoed verbatim; keep it JSON-encodable.
  def update(%{action: :flush} = assigns, socket) do
    {:ok,
     push_event(socket, "leaf-command:#{socket.assigns.id}", %{
       action: "flush",
       ref: Map.get(assigns, :ref)
     })}
  end

  def update(%{action: :mark_saved}, socket) do
    {:ok, push_event(socket, "leaf-command:#{socket.assigns.id}", %{action: "mark_saved"})}
  end

  def update(assigns, socket) do
    {parent_mode, assigns} = Map.pop(assigns, :mode, :hybrid)

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn -> parent_mode end)

    deny = Map.get(socket.assigns, :deny, [])
    validate_deny!(deny)
    mode = normalize_mode(socket.assigns.mode, deny)

    socket = assign(socket, :mode, mode)

    socket =
      assign_new(socket, :visual_html, fn ->
        warn_unpreserved_tags(socket.assigns.content, preserve_tags(socket))

        socket.assigns.content
        |> sanitize_markdown(deny)
        |> markdown_to_html(render_opts(socket))
        |> sanitize_html(deny)
      end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    Process.put(:leaf_gettext_backend, assigns[:gettext_backend])

    deny = assigns[:deny] || []
    validate_deny!(deny)
    allowed_modes = Enum.reject(@mode_order, &mode_denied?(&1, deny))

    {pinned_extra, overflow_extra} =
      Enum.split_with(assigns[:toolbar_extra] || [], &(efetch(&1, :collapse) == false))

    assigns =
      assigns
      |> assign(:suggest_configs, normalized_suggestions(assigns[:suggestions] || []))
      |> assign(:allowed_modes, allowed_modes)
      # A lone tab is a dead affordance — nothing to switch to. Hide the
      # switcher entirely rather than render it.
      |> assign(:show_mode_switcher, length(allowed_modes) > 1)
      |> assign(:pinned_extra, pinned_extra)
      |> assign(:overflow_extra, overflow_extra)

    ~H"""
    <div
      id={@id}
      phx-hook="Leaf"
      class={["min-w-0", @class]}
      style="container-type: inline-size; container-name: leaf-editor;"
      data-leaf-mount-state="loading"
      data-editor-id={@id}
      data-mode={to_string(@mode)}
      data-placeholder={@placeholder}
      data-initial-markdown={@content}
      data-debounce={@debounce}
      data-flush-on-blur={to_string(@flush_on_blur)}
      data-emit-events={to_string(@emit_events)}
      data-preserve-tags={Enum.map_join(@preserve_tags, ",", &String.downcase(to_string(&1)))}
      data-toolbar-layout={to_string(@toolbar_layout)}
      data-readonly={@readonly}
      data-height={@height}
      data-min-height={@min_height}
      data-max-height={@max_height}
      data-maxlength={@maxlength}
      data-smart-typography={to_string(@smart_typography)}
      data-protect-navigation={to_string(@protect_navigation)}
      data-has-upload={to_string(@upload_handler != nil)}
      data-sync-input-name={@sync_input_name}
      data-leaf-js-version={js_version()}
      data-hashtags={to_string(hashtag_trigger?(@suggest_configs))}
      data-collab-operations={to_string(collab_operations?(@collaboration))}
      data-wikilinks={to_string(wiki_links_enabled?(@wiki_links))}
      data-wikilinks-resolve={to_string(wiki_links_resolve?(@wiki_links))}
      data-wikilinks-follow={wiki_links_follow(@wiki_links)}
      data-deny-links={to_string(:links in @deny)}
      data-deny-images={to_string(:images in @deny)}
      data-deny-video={to_string(:video in @deny)}
      data-deny-visual-mode={to_string(:visual_mode in @deny)}
      data-deny-hybrid-mode={to_string(:hybrid_mode in @deny)}
      data-deny-markdown-mode={to_string(:markdown_mode in @deny)}
      data-deny-html-mode={to_string(:html_mode in @deny)}
      data-fallback-mode={to_string(List.first(@allowed_modes))}
    >
      {loading_state_style_tag(@height, @script_nonce)}
      <%= if @bundle_check do %>{bundle_check_script_tag(@script_nonce)}<% end %>

      <%!-- Inline-suggestion trigger configs. Rendered only when the host
           passes `suggestions`, so an editor without them gets exactly the
           markup (and exactly the listeners) it got before this existed. --%>
      <div
        :if={@suggest_configs != []}
        hidden
        data-leaf-suggestions
        data-t-searching={t("Searching…")}
        data-t-no-matches={t("No matches")}
        data-t-create={t("Create")}
        data-t-results={t("results")}
      >
        <span
          :for={s <- @suggest_configs}
          data-leaf-suggest
          data-trigger={s.trigger}
          data-boundary={s.boundary}
          data-token={s.token}
          data-first-char={s.first_char}
          data-min-chars={s.min_chars}
          data-max-length={s.max_length}
          data-debounce={s.debounce}
          data-max-results={s.max_results}
          data-allow-create={s.allow_create}
          data-keep-trigger={s.keep_trigger}
          data-insert-suffix={s.insert_suffix}
          data-label={s.label}
          data-exclude={s.exclude}
        >
        </span>
      </div>

      <%!-- Toolbar --%>
      <div
        id={"#{@id}-toolbar"}
        phx-update="ignore"
        class="flex flex-wrap items-center gap-1 mb-2 p-2 bg-base-200 rounded-lg min-w-0"
        data-visual-toolbar
        data-toolbar-preset={to_string(@preset)}
      >
        <%= unless @readonly do %>
          <div data-visual-toolbar-buttons class="contents">
            <%!-- Undo/Redo --%>
            <div class="flex items-center gap-0.5 mr-2">
              <button
                type="button"
                data-toolbar-action="undo"
                class="btn btn-xs btn-ghost px-2"
                title={t("Undo")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path
                    fill-rule="evenodd"
                    d="M7.793 2.232a.75.75 0 01-.025 1.06L3.622 7.25h10.003a5.375 5.375 0 010 10.75H10.75a.75.75 0 010-1.5h2.875a3.875 3.875 0 000-7.75H3.622l4.146 3.957a.75.75 0 01-1.036 1.085l-5.5-5.25a.75.75 0 010-1.085l5.5-5.25a.75.75 0 011.06.025z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <button
                type="button"
                data-toolbar-action="redo"
                class="btn btn-xs btn-ghost px-2"
                title={t("Redo")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path
                    fill-rule="evenodd"
                    d="M12.207 2.232a.75.75 0 00.025 1.06l4.146 3.958H6.375a5.375 5.375 0 000 10.75H9.25a.75.75 0 000-1.5H6.375a3.875 3.875 0 010-7.75h10.003l-4.146 3.957a.75.75 0 001.036 1.085l5.5-5.25a.75.75 0 000-1.085l-5.5-5.25a.75.75 0 00-1.06.025z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Inline Formatting --%>
            <div class="flex items-center gap-0.5 mr-2">
              <%!-- Headings dropdown --%>
              <%= if @preset == :advanced do %><div class="relative" data-heading-dropdown>
                <button
                  type="button"
                  class="btn btn-xs btn-ghost font-bold px-2"
                  title={t("Headings")}
                  data-heading-trigger
                >
                  <span data-heading-trigger-label>H</span>
                </button>
                <ul
                  class={leaf_menu_class("hidden left-0")}
                  data-leaf-menu
                  data-heading-menu
                >
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="heading1"
                      class="font-bold text-lg"
                    >
                      H1
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="heading2"
                      class="font-bold text-base"
                    >
                      H2
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="heading3"
                      class="font-bold text-sm"
                    >
                      H3
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="heading4"
                      class="font-bold text-xs"
                    >
                      H4
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="heading5"
                      class="font-bold text-xs"
                    >
                      H5
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="heading6"
                      class="font-bold text-xs"
                    >
                      H6
                    </button>
                  </li>
                </ul>
              </div><% end %>
              <button
                type="button"
                data-toolbar-action="bold"
                class="btn btn-xs btn-ghost font-bold px-2"
                title={t("Bold")}
              >
                B
              </button>
              <button
                type="button"
                data-toolbar-action="italic"
                class="btn btn-xs btn-ghost italic px-2"
                title={t("Italic")}
              >
                I
              </button>
              <button
                type="button"
                data-toolbar-action="strike"
                class="btn btn-xs btn-ghost line-through px-2"
                title={t("Strikethrough")}
              >
                S
              </button>
              <%= if @preset == :advanced do %>
                <%!-- More inline formatting --%>
                <div class="relative" data-inline-more-dropdown>
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost px-1.5"
                    title={t("More formatting")}
                    data-inline-more-trigger
                  >
                    <.tool_icon name="ellipsis" />
                  </button>
                  <ul
                    class={leaf_menu_class("hidden left-0")}
                    data-leaf-menu
                    data-inline-more-menu
                  >
                    <li>
                      <button type="button" data-toolbar-action="superscript">
                        <.tool_icon name="superscript" /><span>{t("Superscript")}</span>
                      </button>
                    </li>
                    <li>
                      <button type="button" data-toolbar-action="subscript">
                        <.tool_icon name="subscript" /><span>{t("Subscript")}</span>
                      </button>
                    </li>
                    <li>
                      <button type="button" data-toolbar-action="code">
                        <.tool_icon name="code" /><span>{t("Inline Code")}</span>
                      </button>
                    </li>
                    <li>
                      <button type="button" data-toolbar-action="spoiler">
                        <.tool_icon name="spoiler" /><span>{t("Spoiler")}</span>
                      </button>
                    </li>
                    <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="lists-title">
                      {t("Lists")}
                    </li>
                    <li class="hidden" data-compact-overflow="list-bullet">
                      <button type="button" data-toolbar-action="bulletList">
                        <.tool_icon name="bullet-list" /><span>{t("Bullet List")}</span>
                      </button>
                    </li>
                    <li class="hidden" data-compact-overflow="list-ordered">
                      <button type="button" data-toolbar-action="orderedList">
                        <.tool_icon name="ordered-list" /><span>{t("Numbered List")}</span>
                      </button>
                    </li>
                    <%= if @preset == :advanced do %>
                      <li class="hidden" data-compact-overflow="list-indent">
                        <button type="button" data-toolbar-action="indent">
                          <.tool_icon name="indent" /><span>{t("Increase Indent")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="list-outdent">
                        <button type="button" data-toolbar-action="outdent">
                          <.tool_icon name="outdent" /><span>{t("Decrease Indent")}</span>
                        </button>
                      </li>
                    <% end %>
                    <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="insert-title">
                      {t("Insert")}
                    </li>
                    <%= unless :links in @deny do %>
                      <li class="hidden" data-compact-overflow="insert-link">
                        <button type="button" data-toolbar-action="link">
                          <.tool_icon name="link" /><span>{t("Link")}</span>
                        </button>
                      </li>
                    <% end %>
                    <li class="hidden" data-compact-overflow="insert-emoji">
                      <button type="button" data-toolbar-action="emoji">
                        <.tool_icon name="emoji" /><span>{t("Emoji")}</span>
                      </button>
                    </li>
                    <%= if @preset == :advanced and :image in @toolbar and :images not in @deny do %>
                      <li class="hidden" data-compact-overflow="insert-image">
                        <button type="button" data-toolbar-action="insert-image">
                          <.tool_icon name="image" /><span>{t("Image")}</span>
                        </button>
                      </li>
                    <% end %>
                    <%= if @preset == :advanced and :video in @toolbar and :video not in @deny do %>
                      <li class="hidden" data-compact-overflow="insert-video">
                        <button type="button" data-toolbar-action="insert-video">
                          <.tool_icon name="video" /><span>{t("Video")}</span>
                        </button>
                      </li>
                    <% end %>
                    <%= if @preset == :advanced do %>
                      <li class="hidden" data-compact-overflow="insert-table">
                        <button type="button" data-toolbar-action="table">
                          <.tool_icon name="table" /><span>{t("Table")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-blockquote">
                        <button type="button" data-toolbar-action="blockquote">
                          <.tool_icon name="blockquote" /><span>{t("Blockquote")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-codeblock">
                        <button type="button" data-toolbar-action="codeBlock">
                          <.tool_icon name="code-block" /><span>{t("Code Block")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-hr">
                        <button type="button" data-toolbar-action="horizontalRule">
                          <.tool_icon name="horizontal-rule" /><span>{t("Horizontal Rule")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="taskList">
                          <.tool_icon name="task-list" /><span>{t("Task List")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="callout">
                          <.tool_icon name="callout" /><span>{t("Callout")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="detailsBlock">
                          <.tool_icon name="details" /><span>{t("Details / Accordion")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="symbols">
                          <.tool_icon name="symbols" /><span>{t("Symbols / Date")}</span>
                        </button>
                      </li>
                    <% end %>
                    <li class="hidden" data-compact-overflow="remove-format">
                      <button type="button" data-toolbar-action="removeFormat">
                        <.tool_icon name="remove-format" /><span>{t("Remove Formatting")}</span>
                      </button>
                    </li>
                    <%!-- Only the collapsible half of toolbar_extra gets a
                         mirror row here; buttons marked `collapse: false`
                         stay pinned to the main row, so listing them would
                         duplicate them. --%>
                    <%= if @overflow_extra != [] and not @readonly do %>
                      <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="extra">
                        {t("Components")}
                      </li>
                      <%= for btn <- @overflow_extra do %>
                        <li class="hidden" data-compact-overflow="extra">
                          <button type="button" data-host-action={efetch(btn, :id)}>
                            <.tool_icon name={efetch(btn, :glyph) || "squares-plus"} />
                            <span>{efetch(btn, :label) || efetch(btn, :title) || efetch(btn, :id)}</span>
                          </button>
                        </li>
                      <% end %>
                    <% end %>
                    <%= if @export and not @readonly do %>
                      <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="export">
                        {t("Export")}
                      </li>
                      <li class="hidden" data-compact-overflow="export">
                        <button type="button" data-toolbar-action="copyMarkdown">
                          <.tool_icon name="clipboard" /><span>{t("Copy as Markdown")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="export">
                        <button type="button" data-toolbar-action="copyHtml">
                          <.tool_icon name="clipboard" /><span>{t("Copy as HTML")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="export">
                        <button type="button" data-toolbar-action="downloadMarkdown">
                          <.tool_icon name="download" /><span>{t("Download .md")}</span>
                        </button>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% else %>
                <button
                  type="button"
                  data-toolbar-action="code"
                  class="btn btn-xs btn-ghost px-2"
                  title={t("Inline Code")}
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    class="w-3.5 h-3.5"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M6.28 5.22a.75.75 0 010 1.06L2.56 10l3.72 3.72a.75.75 0 01-1.06 1.06L.97 10.53a.75.75 0 010-1.06l4.25-4.25a.75.75 0 011.06 0zm7.44 0a.75.75 0 011.06 0l4.25 4.25a.75.75 0 010 1.06l-4.25 4.25a.75.75 0 01-1.06-1.06L17.44 10l-3.72-3.72a.75.75 0 010-1.06z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </button>
              <% end %>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="lists"></div>

            <%!-- Lists --%>
            <div class="flex items-center gap-0.5 mr-2" data-toolbar-section="lists">
              <button
                type="button"
                data-toolbar-action="bulletList"
                data-toolbar-overflow="list-bullet"
                class="btn btn-xs btn-ghost px-2"
                title={t("Bullet List")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path
                    fill-rule="evenodd"
                    d="M6 4.75A.75.75 0 016.75 4h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 4.75zM6 10a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 10zm0 5.25a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75a.75.75 0 01-.75-.75zM1.99 4.75a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 15.25a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 10a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1V10z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <button
                type="button"
                data-toolbar-action="orderedList"
                data-toolbar-overflow="list-ordered"
                class="btn btn-xs btn-ghost px-2"
                title={t("Numbered List")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path d="M3.0002 1.25C2.58599 1.25 2.2502 1.58579 2.2502 2C2.2502 2.41421 2.58599 2.75 3.0002 2.75H3.2502V5.25C3.2502 5.66421 3.58599 6 4.0002 6C4.41441 6 4.7502 5.66421 4.7502 5.25V2C4.7502 1.58579 4.41441 1.25 4.0002 1.25H3.0002Z" />
                  <path d="M2.97049 8.65372C3.29513 8.55397 3.64067 8.5 4.0002 8.5C4.16835 8.5 4.33333 8.5118 4.49444 8.53453C4.49127 8.53922 4.48691 8.54312 4.48165 8.54575L2.41479 9.57918C2.1607 9.70622 2.0002 9.96592 2.0002 10.25V11.25C2.0002 11.6642 2.33599 12 2.7502 12H5.2502C5.66441 12 6.0002 11.6642 6.0002 11.25C6.0002 10.8358 5.66441 10.5 5.2502 10.5H3.92725L5.15247 9.88739C5.67202 9.62762 6.0002 9.09661 6.0002 8.51574C6.0002 7.86944 5.57097 7.18897 4.80714 7.06489C4.54401 7.02215 4.27442 7 4.0002 7C3.48967 7 2.99569 7.07676 2.52991 7.21988C2.13397 7.34154 1.91162 7.76115 2.03328 8.15709C2.15494 8.55303 2.57455 8.77538 2.97049 8.65372Z" />
                  <path d="M7.75 3C7.33579 3 7 3.33579 7 3.75C7 4.16421 7.33579 4.5 7.75 4.5H17.25C17.6642 4.5 18 4.16421 18 3.75C18 3.33579 17.6642 3 17.25 3H7.75Z" />
                  <path d="M7.75 9.25C7.33579 9.25 7 9.58579 7 10C7 10.4142 7.33579 10.75 7.75 10.75H17.25C17.6642 10.75 18 10.4142 18 10C18 9.58579 17.6642 9.25 17.25 9.25H7.75Z" />
                  <path d="M7.75 15.5C7.33579 15.5 7 15.8358 7 16.25C7 16.6642 7.33579 17 7.75 17H17.25C17.6642 17 18 16.6642 18 16.25C18 15.8358 17.6642 15.5 17.25 15.5H7.75Z" />
                  <path d="M2.625 13.875C2.21079 13.875 1.875 14.2108 1.875 14.625C1.875 15.0392 2.21079 15.375 2.625 15.375H4.125C4.19404 15.375 4.25 15.431 4.25 15.5C4.25 15.569 4.19404 15.625 4.125 15.625H3.5C3.08579 15.625 2.75 15.9608 2.75 16.375C2.75 16.7892 3.08579 17.125 3.5 17.125H4.125C4.19404 17.125 4.25 17.181 4.25 17.25C4.25 17.319 4.19404 17.375 4.125 17.375H2.625C2.21079 17.375 1.875 17.7108 1.875 18.125C1.875 18.5392 2.21079 18.875 2.625 18.875H4.125C5.02246 18.875 5.75 18.1475 5.75 17.25C5.75 16.9278 5.65625 16.6276 5.49454 16.375C5.65625 16.1224 5.75 15.8222 5.75 15.5C5.75 14.6025 5.02246 13.875 4.125 13.875H2.625Z" />
                </svg>
              </button>
              <%= if @preset == :advanced do %><button
                type="button"
                data-toolbar-action="indent"
                data-toolbar-overflow="list-indent"
                class="btn btn-xs btn-ghost px-2"
                title={t("Increase Indent")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path
                    fill-rule="evenodd"
                    d="M2 3.75A.75.75 0 012.75 3h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 3.75zm0 12.5A.75.75 0 012.75 15.5h14.5a.75.75 0 010 1.5H2.75a.75.75 0 01-.75-.75zM8.75 7.5a.75.75 0 000 1.5h8.5a.75.75 0 000-1.5h-8.5zM8 11.75a.75.75 0 01.75-.75h8.5a.75.75 0 010 1.5h-8.5a.75.75 0 01-.75-.75zM2.22 7.97a.75.75 0 011.06 0L5.03 9.72a.75.75 0 010 1.06l-1.75 1.75a.75.75 0 01-1.06-1.06l1.22-1.22-1.22-1.22a.75.75 0 010-1.06z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <button
                type="button"
                data-toolbar-action="outdent"
                data-toolbar-overflow="list-outdent"
                class="btn btn-xs btn-ghost px-2"
                title={t("Decrease Indent")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path
                    fill-rule="evenodd"
                    d="M2 3.75A.75.75 0 012.75 3h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 3.75zm0 12.5A.75.75 0 012.75 15.5h14.5a.75.75 0 010 1.5H2.75a.75.75 0 01-.75-.75zM8.75 7.5a.75.75 0 000 1.5h8.5a.75.75 0 000-1.5h-8.5zM8 11.75a.75.75 0 01.75-.75h8.5a.75.75 0 010 1.5h-8.5a.75.75 0 01-.75-.75zM5.78 7.97a.75.75 0 010 1.06L4.56 10.25l1.22 1.22a.75.75 0 11-1.06 1.06L2.97 10.78a.75.75 0 010-1.06l1.75-1.75a.75.75 0 011.06 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button><% end %>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="insert"></div>

            <%!-- Insert --%>
            <div class="flex items-center gap-0.5 mr-2" data-toolbar-section="insert">
              <%= unless :links in @deny do %>
                <button
                  type="button"
                  data-toolbar-action="link"
                  data-toolbar-overflow="insert-link"
                  class="btn btn-xs btn-ghost px-2"
                  title={t("Insert Link")}
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    class="w-3.5 h-3.5"
                  >
                    <path d="M12.232 4.232a2.5 2.5 0 013.536 3.536l-1.225 1.224a.75.75 0 001.061 1.06l1.224-1.224a4 4 0 00-5.656-5.656l-3 3a4 4 0 00.225 5.865.75.75 0 00.977-1.138 2.5 2.5 0 01-.142-3.667l3-3z" />
                    <path d="M11.603 7.963a.75.75 0 00-.977 1.138 2.5 2.5 0 01.142 3.667l-3 3a2.5 2.5 0 01-3.536-3.536l1.225-1.224a.75.75 0 00-1.061-1.06l-1.224 1.224a4 4 0 105.656 5.656l3-3a4 4 0 00-.225-5.865z" />
                  </svg>
                </button>
              <% end %>
              <button
                type="button"
                data-toolbar-action="emoji"
                data-toolbar-overflow="insert-emoji"
                class="btn btn-xs btn-ghost px-2"
                title={t("Insert Emoji")}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.536-4.464a.75.75 0 10-1.06-1.06 3.5 3.5 0 01-4.95 0 .75.75 0 00-1.06 1.06 5 5 0 007.07 0zM9 8.5c0 .828-.448 1.5-1 1.5s-1-.672-1-1.5S7.448 7 8 7s1 .672 1 1.5zm3 1.5c.552 0 1-.672 1-1.5S12.552 7 12 7s-1 .672-1 1.5.448 1.5 1 1.5z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <%= if @preset == :advanced and :image in @toolbar and :images not in @deny do %>
                <div class="relative inline-flex" data-image-split-btn data-toolbar-overflow="insert-image">
                  <button
                    type="button"
                    data-toolbar-action="insert-image"
                    class="btn btn-xs btn-ghost px-2 rounded-r-none"
                    title={t("Insert Image")}
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                      class="w-3.5 h-3.5"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M1 5.25A2.25 2.25 0 013.25 3h13.5A2.25 2.25 0 0119 5.25v9.5A2.25 2.25 0 0116.75 17H3.25A2.25 2.25 0 011 14.75v-9.5zm1.5 5.81v3.69c0 .414.336.75.75.75h13.5a.75.75 0 00.75-.75v-2.69l-2.22-2.219a.75.75 0 00-1.06 0l-1.91 1.909-4.97-4.969a.75.75 0 00-1.06 0L2.5 11.06zm10-3.56a1.5 1.5 0 113 0 1.5 1.5 0 01-3 0z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </button>
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost px-0.5 rounded-l-none border-l border-base-300"
                    title={t("Image options")}
                    data-image-dropdown-trigger
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                      class="w-3 h-3"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </button>
                  <ul
                    class={leaf_menu_class("hidden left-0 !z-[10000]")}
                    data-leaf-menu
                    data-image-dropdown-menu
                  >
                    <li>
                      <button type="button" data-toolbar-action="insert-image-upload">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                          <path d="M9.25 13.25a.75.75 0 0 0 1.5 0V4.636l2.955 3.129a.75.75 0 0 0 1.09-1.03l-4.25-4.5a.75.75 0 0 0-1.09 0l-4.25 4.5a.75.75 0 1 0 1.09 1.03L9.25 4.636v8.614Z" />
                          <path d="M3.5 12.75a.75.75 0 0 0-1.5 0v2.5A2.75 2.75 0 0 0 4.75 18h10.5A2.75 2.75 0 0 0 18 15.25v-2.5a.75.75 0 0 0-1.5 0v2.5c0 .69-.56 1.25-1.25 1.25H4.75c-.69 0-1.25-.56-1.25-1.25v-2.5Z" />
                        </svg>
                        <span>{t("Upload")}</span>
                      </button>
                    </li>
                    <li>
                      <button type="button" data-toolbar-action="insert-image-url">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                          <path d="M12.232 4.232a2.5 2.5 0 013.536 3.536l-1.225 1.224a.75.75 0 001.061 1.06l1.224-1.224a4 4 0 00-5.656-5.656l-3 3a4 4 0 00.225 5.865.75.75 0 00.977-1.138 2.5 2.5 0 01-.142-3.667l3-3z" />
                          <path d="M11.603 7.963a.75.75 0 00-.977 1.138 2.5 2.5 0 01.142 3.667l-3 3a2.5 2.5 0 01-3.536-3.536l1.225-1.224a.75.75 0 00-1.061-1.06l-1.224 1.224a4 4 0 105.656 5.656l3-3a4 4 0 00-.225-5.865z" />
                        </svg>
                        <span>{t("By URL")}</span>
                      </button>
                    </li>
                  </ul>
                </div>
              <% end %>
              <%= if @preset == :advanced and :video in @toolbar and :video not in @deny do %>
                <button
                  type="button"
                  data-toolbar-action="insert-video"
                  data-toolbar-overflow="insert-video"
                  class="btn btn-xs btn-ghost px-2"
                  title={t("Insert Video")}
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    class="w-3.5 h-3.5"
                  >
                    <path d="M3.25 4A2.25 2.25 0 001 6.25v7.5A2.25 2.25 0 003.25 16h7.5A2.25 2.25 0 0013 13.75v-7.5A2.25 2.25 0 0010.75 4h-7.5zM19 4.75a.75.75 0 00-1.28-.53l-3 3a.75.75 0 00-.22.53v4.5c0 .199.079.39.22.53l3 3A.75.75 0 0019 15.25v-10.5z" />
                  </svg>
                </button>
              <% end %>
              <%= if @preset == :advanced do %><%!-- Table dropdown --%>
              <div class="relative" data-table-dropdown data-toolbar-overflow="insert-table">
                <button
                  type="button"
                  class="btn btn-xs btn-ghost px-2"
                  title={t("Table")}
                  data-table-trigger
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    class="w-3.5 h-3.5"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M.99 5.24A2.25 2.25 0 0 1 3.25 3h13.5A2.25 2.25 0 0 1 19 5.25l.01 9.5A2.25 2.25 0 0 1 16.76 17H3.26A2.267 2.267 0 0 1 1 14.74l-.01-9.5Zm8.26 9.52v-.625a.75.75 0 0 0-.75-.75H3.25a.75.75 0 0 0-.75.75v.615c0 .414.336.75.75.75h5.373a.75.75 0 0 0 .627-.74Zm1.5 0a.75.75 0 0 0 .627.74h5.373a.75.75 0 0 0 .75-.75v-.615a.75.75 0 0 0-.75-.75H11.5a.75.75 0 0 0-.75.75v.625Zm6.75-3.63v-.625a.75.75 0 0 0-.75-.75H11.5a.75.75 0 0 0-.75.75v.625c0 .414.336.75.75.75h5.25a.75.75 0 0 0 .75-.75Zm-8.25 0v-.625a.75.75 0 0 0-.75-.75H3.25a.75.75 0 0 0-.75.75v.625c0 .414.336.75.75.75H8.5a.75.75 0 0 0 .75-.75ZM17.5 7.5v-.625a.75.75 0 0 0-.75-.75H11.5a.75.75 0 0 0-.75.75V7.5c0 .414.336.75.75.75h5.25a.75.75 0 0 0 .75-.75Zm-8.25 0v-.625a.75.75 0 0 0-.75-.75H3.25a.75.75 0 0 0-.75.75V7.5c0 .414.336.75.75.75H8.5a.75.75 0 0 0 .75-.75Z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </button>
                <ul
                  class={leaf_menu_class("hidden left-0")}
                  data-leaf-menu
                  data-table-menu
                >
                  <li>
                    <button type="button" data-toolbar-action="table">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path fill-rule="evenodd" d="M.99 5.24A2.25 2.25 0 013.25 3h13.5A2.25 2.25 0 0119 5.25v9.5A2.25 2.25 0 0116.75 17H3.25A2.25 2.25 0 011 14.75v-9.5zm1.5 0v2.5h7v-3H3.25a.75.75 0 00-.75.75zm8.5-.75v3h7v-2.5a.75.75 0 00-.75-.75h-6.25zM2.5 9.25v2.5h7v-2.5h-7zm8.5 0v2.5h7v-2.5h-7zM2.5 13.25v1.5c0 .414.336.75.75.75h6.25v-2.25h-7zm8.5 0v2.25h6.25a.75.75 0 00.75-.75v-1.5h-7z" clip-rule="evenodd" />
                      </svg>
                      <span>{t("Insert Table")}</span>
                    </button>
                  </li>
                  <li class="menu-title text-xs px-2 pt-1">{t("Rows")}</li>
                  <li>
                    <button type="button" data-toolbar-action="tableAddRow">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path d="M10.75 4.75a.75.75 0 0 0-1.5 0v4.5h-4.5a.75.75 0 0 0 0 1.5h4.5v4.5a.75.75 0 0 0 1.5 0v-4.5h4.5a.75.75 0 0 0 0-1.5h-4.5v-4.5Z" />
                      </svg>
                      <span>{t("Add Row Below")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="tableRemoveRow">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path fill-rule="evenodd" d="M4 10a.75.75 0 0 1 .75-.75h10.5a.75.75 0 0 1 0 1.5H4.75A.75.75 0 0 1 4 10Z" clip-rule="evenodd" />
                      </svg>
                      <span>{t("Remove Row")}</span>
                    </button>
                  </li>
                  <li class="menu-title text-xs px-2 pt-1">{t("Columns")}</li>
                  <li>
                    <button type="button" data-toolbar-action="tableAddCol">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path d="M10.75 4.75a.75.75 0 0 0-1.5 0v4.5h-4.5a.75.75 0 0 0 0 1.5h4.5v4.5a.75.75 0 0 0 1.5 0v-4.5h4.5a.75.75 0 0 0 0-1.5h-4.5v-4.5Z" />
                      </svg>
                      <span>{t("Add Column Right")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="tableRemoveCol">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path fill-rule="evenodd" d="M4 10a.75.75 0 0 1 .75-.75h10.5a.75.75 0 0 1 0 1.5H4.75A.75.75 0 0 1 4 10Z" clip-rule="evenodd" />
                      </svg>
                      <span>{t("Remove Column")}</span>
                    </button>
                  </li>
                  <li class="menu-title text-xs px-2 pt-1">{t("Column align")}</li>
                  <li>
                    <button type="button" data-toolbar-action="tableAlignLeft">
                      <span class="font-mono text-xs">⌑</span><span>{t("Align Left")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="tableAlignCenter">
                      <span class="font-mono text-xs">⌑</span><span>{t("Align Center")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="tableAlignRight">
                      <span class="font-mono text-xs">⌑</span><span>{t("Align Right")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="tableToggleHeader">
                      <span class="font-mono text-xs">▤</span><span>{t("Toggle Header Row")}</span>
                    </button>
                  </li>
                </ul>
              </div>
              <%!-- More inserts --%>
              <div class="relative" data-insert-more-dropdown data-toolbar-overflow="insert-more">
                <button
                  type="button"
                  class="btn btn-xs btn-ghost px-1.5"
                  title={t("More inserts")}
                  data-insert-more-trigger
                >
                  <%!-- Same ellipsis as "More formatting": every overflow
                       trigger means "more of this section", and the section
                       dividers already tell them apart. --%>
                  <.tool_icon name="ellipsis" />
                </button>
                <ul
                  class={leaf_menu_class("hidden left-0")}
                  data-leaf-menu
                  data-insert-more-menu
                >
                  <li>
                    <button type="button" data-toolbar-action="blockquote">
                      <.tool_icon name="blockquote" /><span>{t("Blockquote")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="codeBlock">
                      <.tool_icon name="code-block" /><span>{t("Code Block")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="horizontalRule">
                      <.tool_icon name="horizontal-rule" /><span>{t("Horizontal Rule")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="detailsBlock">
                      <.tool_icon name="details" /><span>{t("Details / Accordion")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="taskList">
                      <.tool_icon name="task-list" /><span>{t("Task List")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="callout">
                      <.tool_icon name="callout" /><span>{t("Callout")}</span>
                    </button>
                  </li>
                  <li>
                    <button type="button" data-toolbar-action="symbols">
                      <.tool_icon name="symbols" /><span>{t("Symbols / Date")}</span>
                    </button>
                  </li>
                </ul>
              </div>
              <% end %>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="remove-format"></div>

            <%!-- Clear Formatting --%>
            <div class="flex items-center gap-0.5" data-toolbar-section="remove-format">
              <button
                type="button"
                data-toolbar-action="removeFormat"
                data-toolbar-overflow="remove-format"
                class="btn btn-xs btn-ghost px-2"
                title={t("Remove Formatting")}
              >
                <.tool_icon name="remove-format" />
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Host-defined toolbar buttons (toolbar_extra). Rendered as a
             sibling of the formatting buttons so they stay visible across
             every mode (including HTML, where the formatting buttons hide).
             Each click pushes "toolbar_action" with the button id + the
             current selection; the host LiveView receives
             {:leaf_toolbar_action, %{editor_id, id, selection}}. --%>
        <%!-- Buttons marked `collapse: false` are the host's primary
             actions — the components its documents are built from — so
             they render in a group with no `data-toolbar-overflow` key and
             the compact CSS never folds them into the "More" menu. The
             rest keep the original collapse-on-narrow behaviour. --%>
        <%= if @pinned_extra != [] and not @readonly do %>
          <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="extra-pinned"></div>
          <div class="flex items-center gap-0.5" data-toolbar-extra data-toolbar-extra-pinned>
            <.toolbar_extra_button :for={btn <- @pinned_extra} btn={btn} />
          </div>
        <% end %>
        <%= if @overflow_extra != [] and not @readonly do %>
          <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="extra"></div>
          <div class="flex items-center gap-0.5" data-toolbar-extra data-toolbar-overflow="extra">
            <.toolbar_extra_button :for={btn <- @overflow_extra} btn={btn} />
          </div>
        <% end %>

        <%!-- Export / copy (opt-in via export={true}). Client-side actions
             reading the current markdown/HTML; no server round-trip. --%>
        <%= if @export and not @readonly do %>
          <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="export"></div>
          <div class="flex items-center gap-0.5" data-toolbar-export data-toolbar-overflow="export">
            <button type="button" data-toolbar-action="copyMarkdown" class="btn btn-xs btn-ghost px-2" title={t("Copy as Markdown")}>
              <span class="text-xs font-semibold">MD</span>
            </button>
            <button type="button" data-toolbar-action="copyHtml" class="btn btn-xs btn-ghost px-2" title={t("Copy as HTML")}>
              <span class="text-xs font-semibold">HTML</span>
            </button>
            <button type="button" data-toolbar-action="downloadMarkdown" class="btn btn-xs btn-ghost px-2" title={t("Download .md")}>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M10.75 2.75a.75.75 0 0 0-1.5 0v8.614L6.295 8.235a.75.75 0 1 0-1.09 1.03l4.25 4.5a.75.75 0 0 0 1.09 0l4.25-4.5a.75.75 0 0 0-1.09-1.03l-2.955 3.129V2.75Z" />
                <path d="M3.5 12.75a.75.75 0 0 0-1.5 0v2.5A2.75 2.75 0 0 0 4.75 18h10.5A2.75 2.75 0 0 0 18 15.25v-2.5a.75.75 0 0 0-1.5 0v2.5c0 .69-.56 1.25-1.25 1.25H4.75c-.69 0-1.25-.56-1.25-1.25v-2.5Z" />
              </svg>
            </button>
          </div>
        <% end %>

        <%!-- Spacer --%>
        <div class="flex-1"></div>

        <%!-- Mode Switcher. Every tab is gated on the deny list, and the
             whole switcher disappears when only one mode survives — a lone
             tab switches to nothing. --%>
        <div :if={@show_mode_switcher} class="flex items-center gap-0.5" data-mode-switcher="inline">
          <div class="divider divider-horizontal mx-0.5 h-6"></div>
          <%= if :hybrid in @allowed_modes do %>
            <button
              type="button"
              data-mode-tab="hybrid"
              class={["btn btn-xs px-2", (@mode == :hybrid && "btn-active") || "btn-ghost"]}
              title={t("Hybrid mode")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                class="w-3.5 h-3.5"
              >
                <path
                  fill-rule="evenodd"
                  d="M9 4.5a.75.75 0 0 1 .721.544l.813 2.846a3.75 3.75 0 0 0 2.576 2.576l2.846.813a.75.75 0 0 1 0 1.442l-2.846.813a3.75 3.75 0 0 0-2.576 2.576l-.813 2.846a.75.75 0 0 1-1.442 0l-.813-2.846a3.75 3.75 0 0 0-2.576-2.576L1.044 12.22a.75.75 0 0 1 0-1.442l2.846-.813A3.75 3.75 0 0 0 6.466 7.39l.813-2.846A.75.75 0 0 1 9 4.5Z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
          <% end %>
          <%= if :visual in @allowed_modes do %>
            <button
              type="button"
              data-mode-tab="visual"
              class={["btn btn-xs px-2", (@mode == :visual && "btn-active") || "btn-ghost"]}
              title={t("Visual mode")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                class="w-3.5 h-3.5"
              >
                <path d="M10 12.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5z" />
                <path
                  fill-rule="evenodd"
                  d="M.664 10.59a1.651 1.651 0 010-1.186A10.004 10.004 0 0110 3c4.257 0 7.893 2.66 9.336 6.41.147.381.146.804 0 1.186A10.004 10.004 0 0110 17c-4.257 0-7.893-2.66-9.336-6.41zM14 10a4 4 0 11-8 0 4 4 0 018 0z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
          <% end %>
          <%= if :markdown in @allowed_modes do %>
            <button
              type="button"
              data-mode-tab="markdown"
              class={["btn btn-xs px-2", (@mode == :markdown && "btn-active") || "btn-ghost"]}
              title={t("Markdown mode")}
            >
              <svg viewBox="0 0 208 128" fill="currentColor" class="w-4 h-3">
                <path d="M30 98V30h20l20 25 20-25h20v68H90V59L70 84 50 59v39zm125 0l-30-33h20V30h20v35h20z" />
              </svg>
            </button>
          <% end %>
          <%= if :html in @allowed_modes do %>
            <button
              type="button"
              data-mode-tab="html"
              class={["btn btn-xs px-2", (@mode == :html && "btn-active") || "btn-ghost"]}
              title={t("HTML mode")}
            >
              &lt;/&gt;
            </button>
          <% end %>
        </div>

        <%!-- Fullscreen toggle (advanced preset only) --%>
        <%= if @preset == :advanced do %>
          <div class="flex items-center gap-0.5" data-toolbar-section="fullscreen">
            <div class="divider divider-horizontal mx-0.5 h-6"></div>
            <button
              type="button"
              data-toolbar-action="fullscreen"
              data-leaf-fullscreen-btn
              class="btn btn-xs btn-ghost px-2"
              title={t("Toggle fullscreen")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="w-3.5 h-3.5"
                data-leaf-fullscreen-enter
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
                />
              </svg>
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="w-3.5 h-3.5"
                data-leaf-fullscreen-exit
                style="display:none"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 9V4.5M9 9H4.5M9 9 3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5l5.25 5.25"
                />
              </svg>
            </button>
          </div>
        <% end %>

        <details class="relative hidden" data-mode-switcher-compact>
          <summary
            class="btn btn-xs btn-ghost px-1.5 cursor-pointer"
            title={t("More editor options")}
            aria-label={t("More editor options")}
          >
            <span class="text-base font-bold leading-none">&#8942;</span>
          </summary>
          <ul
            class={leaf_menu_class("right-0")}
            data-leaf-menu
            data-mode-menu
          >
            <%= if @show_mode_switcher do %>
              <li class="menu-title text-xs px-2 pt-1">{t("Mode")}</li>
              <li :if={:hybrid in @allowed_modes}>
                <button
                  type="button"
                  data-mode-tab="hybrid"
                  class={(@mode == :hybrid && "btn-active") || "btn-ghost"}
                >
                  <span>{t("Hybrid")}</span>
                </button>
              </li>
              <li :if={:visual in @allowed_modes}>
                <button
                  type="button"
                  data-mode-tab="visual"
                  class={(@mode == :visual && "btn-active") || "btn-ghost"}
                >
                  <span>{t("Visual")}</span>
                </button>
              </li>
              <li :if={:markdown in @allowed_modes}>
                <button
                  type="button"
                  data-mode-tab="markdown"
                  class={(@mode == :markdown && "btn-active") || "btn-ghost"}
                >
                  <span>{t("Markdown")}</span>
                </button>
              </li>
              <li :if={:html in @allowed_modes}>
                <button
                  type="button"
                  data-mode-tab="html"
                  class={(@mode == :html && "btn-active") || "btn-ghost"}
                >
                  <span>{t("HTML")}</span>
                </button>
              </li>
            <% end %>
            <%= if @preset == :advanced do %>
              <li class="menu-title text-xs px-2 pt-1">{t("View")}</li>
              <li>
                <button type="button" data-toolbar-action="fullscreen">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="2"
                    stroke="currentColor"
                    class="w-3.5 h-3.5"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
                    />
                  </svg>
                  <span>{t("Fullscreen")}</span>
                </button>
              </li>
            <% end %>
          </ul>
        </details>
      </div>

      <%= unless @readonly do %>
        <%!-- Mobile writing toolbar --%>
        <div
          id={"#{@id}-mobile-toolbar"}
          phx-update="ignore"
          class="hidden items-center gap-1 mb-2 p-1.5 bg-base-200 rounded-lg min-w-0"
          data-mobile-toolbar
          data-toolbar-preset={to_string(@preset)}
        >
          <button
            type="button"
            data-toolbar-action="bold"
            class="btn btn-sm btn-ghost font-bold px-3"
            title={t("Bold")}
          >
            B
          </button>
          <button
            type="button"
            data-toolbar-action="italic"
            class="btn btn-sm btn-ghost italic px-3"
            title={t("Italic")}
          >
            I
          </button>
          <%= unless :links in @deny do %>
            <button
              type="button"
              data-toolbar-action="link"
              class="btn btn-sm btn-ghost px-2.5"
              title={t("Link")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                class="w-4 h-4"
              >
                <path d="M12.232 4.232a2.5 2.5 0 013.536 3.536l-1.225 1.224a.75.75 0 001.061 1.06l1.224-1.224a4 4 0 00-5.656-5.656l-3 3a4 4 0 00.225 5.865.75.75 0 00.977-1.138 2.5 2.5 0 01-.142-3.667l3-3z" />
                <path d="M11.603 7.963a.75.75 0 00-.977 1.138 2.5 2.5 0 01.142 3.667l-3 3a2.5 2.5 0 01-3.536-3.536l1.225-1.224a.75.75 0 00-1.061-1.06l-1.224 1.224a4 4 0 105.656 5.656l3-3a4 4 0 00-.225-5.865z" />
              </svg>
            </button>
          <% end %>
          <button
            type="button"
            data-toolbar-action="bulletList"
            class="btn btn-sm btn-ghost px-2.5"
            title={t("Bullet List")}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-4 h-4"
            >
              <path
                fill-rule="evenodd"
                d="M6 4.75A.75.75 0 016.75 4h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 4.75zM6 10a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 10zm0 5.25a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75a.75.75 0 01-.75-.75zM1.99 4.75a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 15.25a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 10a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1V10z"
                clip-rule="evenodd"
              />
            </svg>
          </button>

          <details class="relative" data-mobile-tools-menu>
            <summary
              class="btn btn-sm btn-ghost px-2.5 cursor-pointer"
              title={t("More formatting")}
              aria-label={t("More formatting")}
            >
              <.tool_icon name="ellipsis" class="w-4 h-4" />
            </summary>
            <ul class={leaf_menu_class("left-0")} data-leaf-menu>
              <li class="menu-title text-xs px-2 pt-1">{t("Format")}</li>
              <li>
                <button type="button" data-toolbar-action="heading2">
                  <.tool_icon name="heading" /><span>{t("Heading")}</span>
                </button>
              </li>
              <li>
                <button type="button" data-toolbar-action="orderedList">
                  <.tool_icon name="ordered-list" /><span>{t("Numbered List")}</span>
                </button>
              </li>
              <li>
                <button type="button" data-toolbar-action="code">
                  <.tool_icon name="code" /><span>{t("Inline Code")}</span>
                </button>
              </li>
              <%= if @preset == :advanced do %>
                <li>
                  <button type="button" data-toolbar-action="blockquote">
                    <.tool_icon name="blockquote" /><span>{t("Blockquote")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="codeBlock">
                    <.tool_icon name="code-block" /><span>{t("Code Block")}</span>
                  </button>
                </li>
                <li class="menu-title text-xs px-2 pt-1">{t("Insert")}</li>
                <li>
                  <button type="button" data-toolbar-action="horizontalRule">
                    <.tool_icon name="horizontal-rule" /><span>{t("Horizontal Rule")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="taskList">
                    <.tool_icon name="task-list" /><span>{t("Task List")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="callout">
                    <.tool_icon name="callout" /><span>{t("Callout")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="detailsBlock">
                    <.tool_icon name="details" /><span>{t("Details / Accordion")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="symbols">
                    <.tool_icon name="symbols" /><span>{t("Symbols / Date")}</span>
                  </button>
                </li>
                <%= if :image in @toolbar and :images not in @deny do %>
                  <li>
                    <button type="button" data-toolbar-action="insert-image">
                      <.tool_icon name="image" /><span>{t("Image")}</span>
                    </button>
                  </li>
                <% end %>
                <%= if :video in @toolbar and :video not in @deny do %>
                  <li>
                    <button type="button" data-toolbar-action="insert-video">
                      <.tool_icon name="video" /><span>{t("Video")}</span>
                    </button>
                  </li>
                <% end %>
              <% end %>
              <%= if @toolbar_extra != [] and not @readonly do %>
                <li class="menu-title text-xs px-2 pt-1">{t("Components")}</li>
                <%= for btn <- @toolbar_extra do %>
                  <li>
                    <button type="button" data-host-action={efetch(btn, :id)}>
                      <.tool_icon name={efetch(btn, :glyph) || "squares-plus"} />
                      <span>{efetch(btn, :label) || efetch(btn, :title) || efetch(btn, :id)}</span>
                    </button>
                  </li>
                <% end %>
              <% end %>
              <%= if @export and not @readonly do %>
                <li class="menu-title text-xs px-2 pt-1">{t("Export")}</li>
                <li>
                  <button type="button" data-toolbar-action="copyMarkdown">
                    <.tool_icon name="clipboard" /><span>{t("Copy as Markdown")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="copyHtml">
                    <.tool_icon name="clipboard" /><span>{t("Copy as HTML")}</span>
                  </button>
                </li>
                <li>
                  <button type="button" data-toolbar-action="downloadMarkdown">
                    <.tool_icon name="download" /><span>{t("Download .md")}</span>
                  </button>
                </li>
              <% end %>
              <li class="menu-title text-xs px-2 pt-1">{t("Clean up")}</li>
              <li>
                <button type="button" data-toolbar-action="removeFormat">
                  <.tool_icon name="remove-format" /><span>{t("Remove Formatting")}</span>
                </button>
              </li>
            </ul>
          </details>

          <div class="flex-1"></div>

          <details class="relative" data-mobile-options-menu>
            <summary
              class="btn btn-sm btn-ghost px-2.5 cursor-pointer"
              title={t("More editor options")}
              aria-label={t("More editor options")}
            >
              <span class="text-base font-bold leading-none">&#8942;</span>
            </summary>
            <ul class={leaf_menu_class("right-0")} data-leaf-menu>
              <%= if @show_mode_switcher do %>
                <li class="menu-title text-xs px-2 pt-1">{t("Mode")}</li>
                <li :if={:hybrid in @allowed_modes}>
                  <button
                    type="button"
                    data-mode-tab="hybrid"
                    class={(@mode == :hybrid && "btn-active") || "btn-ghost"}
                  >
                    <.tool_icon name="sparkles" /><span>{t("Hybrid")}</span>
                  </button>
                </li>
                <li :if={:visual in @allowed_modes}>
                  <button
                    type="button"
                    data-mode-tab="visual"
                    class={(@mode == :visual && "btn-active") || "btn-ghost"}
                  >
                    <.tool_icon name="eye" /><span>{t("Visual")}</span>
                  </button>
                </li>
                <li :if={:markdown in @allowed_modes}>
                  <button
                    type="button"
                    data-mode-tab="markdown"
                    class={(@mode == :markdown && "btn-active") || "btn-ghost"}
                  >
                    <.tool_icon name="markdown" /><span>{t("Markdown")}</span>
                  </button>
                </li>
                <li :if={:html in @allowed_modes}>
                  <button
                    type="button"
                    data-mode-tab="html"
                    class={(@mode == :html && "btn-active") || "btn-ghost"}
                  >
                    <.tool_icon name="html" /><span>{t("HTML")}</span>
                  </button>
                </li>
              <% end %>
              <%= if @preset == :advanced do %>
                <li class="menu-title text-xs px-2 pt-1">{t("View")}</li>
                <li>
                  <button type="button" data-toolbar-action="fullscreen">
                    <.tool_icon name="fullscreen" /><span>{t("Fullscreen")}</span>
                  </button>
                </li>
              <% end %>
            </ul>
          </details>
        </div>
      <% end %>

      <div
        class="border border-base-300 overflow-hidden"
        style="border-radius: 0.5rem"
        data-leaf-body-wrapper
      >
        <div data-leaf-loading>
          <span>{@loading_text || loading_preset_text(resolve_loading_preset(@loading_preset))}</span>
        </div>

        <div data-leaf-content>
        <%!-- Visual Editor (contenteditable) --%>
        <div data-visual-wrapper class={["relative", @mode not in [:visual, :hybrid] && "hidden"]}>
          <%!-- Block drag handle (positioned by JS) --%>
          <div data-drag-handle class="leaf-drag-handle" style="display:none">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor">
              <circle cx="5.5" cy="3.5" r="1.5" /><circle cx="10.5" cy="3.5" r="1.5" />
              <circle cx="5.5" cy="8" r="1.5" /><circle cx="10.5" cy="8" r="1.5" />
              <circle cx="5.5" cy="12.5" r="1.5" /><circle cx="10.5" cy="12.5" r="1.5" />
            </svg>
          </div>
          <div
            id={"#{@id}-visual"}
            data-editor-visual
            phx-update="ignore"
            contenteditable={if @readonly, do: "false", else: "true"}
            autocapitalize="sentences"
            autocorrect="on"
            dir={@dir}
            spellcheck={to_string(@spellcheck)}
            class={[
              "content-editor-visual",
              "overflow-auto p-4 pl-10",
              "focus:outline-none",
              @readonly && "opacity-70 cursor-not-allowed"
            ]}
            style={surface_style(@height, @min_height, @max_height)}
          >
            {raw(@visual_html)}
          </div>
        </div>

        <%!-- Markdown Mode: Plain textarea --%>
        <div data-markdown-wrapper class={[@mode != :markdown && "hidden"]}>
          <textarea
            id={"#{@id}-markdown-textarea"}
            phx-update="ignore"
            class={[
              "textarea w-full font-mono text-sm leading-relaxed border-0 rounded-none focus:outline-none focus:ring-0",
              @readonly && "opacity-70 cursor-not-allowed"
            ]}
            style={surface_style(@height, @min_height, @max_height)}
            placeholder={@placeholder}
            readonly={@readonly}
            maxlength={@maxlength}
            spellcheck={to_string(@spellcheck)}
            dir={@dir}
            phx-debounce={@debounce}
          ><%= @content %></textarea>
        </div>

        <%!-- HTML Mode: Plain textarea --%>
        <div data-html-wrapper class={[@mode != :html && "hidden"]}>
          <textarea
            id={"#{@id}-html-textarea"}
            phx-update="ignore"
            class={[
              "textarea w-full font-mono text-sm leading-relaxed border-0 rounded-none focus:outline-none focus:ring-0",
              @readonly && "opacity-70 cursor-not-allowed"
            ]}
            style={surface_style(@height, @min_height, @max_height)}
            placeholder="<p>Write HTML here...</p>"
            readonly={@readonly}
            phx-debounce={@debounce}
          ><%= @visual_html %></textarea>
        </div>
        </div>

        <div class="flex items-center justify-between gap-4 px-3 py-1 text-xs text-base-content/50 border-t border-base-300">
          <%!-- Save-status badge: server-driven (NOT inside the ignored
               counts block), so updating the save_status assign re-renders it. --%>
          <span :if={@save_status} class="flex items-center gap-1">
            <span
              class="inline-block w-1.5 h-1.5 rounded-full"
              style={save_status_dot(@save_status)}
            >
            </span>
            {save_status_label(@save_status)}
          </span>
          <span :if={!@save_status}></span>
          <div id={"#{@id}-footer"} phx-update="ignore" data-editor-footer class="flex gap-4">
            <span data-word-count>0 words</span>
            <span data-char-count>0 chars</span>
            <span data-reading-time>0 min read</span>
            <span data-maxlength-count></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Editor-surface sizing. `height="auto"` enables auto-grow: the surface
  # sizes to its content between min_height and max_height (the textareas
  # also get a JS resize-to-content hook). A fixed height keeps the classic
  # user-resizable box.
  defp surface_style("auto", min_h, max_h) do
    [
      "min-height: ",
      min_h || "8rem",
      "; height: auto;",
      if(max_h, do: " max-height: #{max_h}; overflow: auto;", else: "")
    ]
    |> Enum.join()
  end

  defp surface_style(height, _min_h, _max_h) do
    "min-height: #{height}; height: #{height}; resize: vertical;"
  end

  defp save_status_label(:saved), do: t("Saved")
  defp save_status_label(:saving), do: t("Saving…")
  defp save_status_label(:unsaved), do: t("Unsaved changes")
  defp save_status_label(_), do: ""

  defp save_status_dot(:saved), do: "background:#22c55e;"
  defp save_status_dot(:saving), do: "background:#eab308;"
  defp save_status_dot(:unsaved), do: "background:#9ca3af;"
  defp save_status_dot(_), do: "background:transparent;"

  # Shared geometry for every toolbar dropdown.
  #
  # `min-w-max` lets the widest row size the menu, instead of the old fixed
  # `w-40`/`w-44` that clipped or wrapped labels like "Details / Accordion"
  # once they gained a leading icon. The max-width clamps to the viewport on
  # a phone, and the max-height keeps a twenty-row menu scrollable instead
  # of running off the bottom of the screen.
  #
  # Row height, nowrap and the flip/clamp behaviour live in the injected CSS
  # + the `data-leaf-menu` handling in the hook, so they don't depend on the
  # host's Tailwind picking up arbitrary variants from this file.
  defp leaf_menu_class(extra) do
    [
      "absolute top-full menu bg-base-200 rounded-box z-50 p-1 shadow-lg",
      "min-w-max max-w-[min(20rem,calc(100vw-1.5rem))]",
      # `flex-nowrap` is load-bearing: daisyUI's `.menu` sets `flex-wrap:
      # wrap`, so capping the height below the content height makes rows
      # spill into a SECOND COLUMN instead of scrolling.
      "flex-col flex-nowrap max-h-[min(70vh,28rem)] overflow-y-auto",
      extra
    ]
  end

  # -- Toolbar icons --

  # One fixed-size slot for every menu row and compact button, so a menu
  # mixing icon rows with text-glyph rows (Ω, X², H) still has a straight
  # left edge. Rows with no icon at all pass an unknown name and get an
  # empty slot of the same width rather than shifting their label left.
  #
  # Glyphs are either a list of SVG path `d` strings or a short string
  # rendered as text. Framed icons (code block, details) put the frame and
  # its contents in a SINGLE `d` so `fill-rule="evenodd"` punches the inner
  # shape out — separate `<path>` elements would each fill independently
  # and the frame would come out solid.
  attr(:name, :string, required: true)
  attr(:class, :string, default: "w-3.5 h-3.5")

  defp tool_icon(assigns) do
    assigns = assign(assigns, :glyph, tool_glyph(assigns.name))

    ~H"""
    <span
      class="inline-flex w-4 h-4 shrink-0 items-center justify-center"
      aria-hidden="true"
    >
      <svg
        :if={is_list(@glyph)}
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
        class={@class}
      >
        <path :for={d <- @glyph} fill-rule="evenodd" clip-rule="evenodd" d={d} />
      </svg>
      <span :if={is_binary(@glyph)} class="text-[0.7rem] font-semibold leading-none">
        {@glyph}
      </span>
    </span>
    """
  end

  # One host-defined toolbar button. `:icon` is rendered raw so hosts can
  # pass an inline `<svg>` — see the `toolbar_extra` attr docs; that makes
  # it trusted markup and never safe to build from user input.
  attr(:btn, :map, required: true)

  defp toolbar_extra_button(assigns) do
    ~H"""
    <button
      type="button"
      data-host-action={efetch(@btn, :id)}
      class={["btn btn-xs btn-ghost px-2", efetch(@btn, :class)]}
      title={efetch(@btn, :title)}
      aria-label={efetch(@btn, :title)}
    >
      <%= if icon = efetch(@btn, :icon) do %>{raw(icon)}<% end %>
      <%= if label = efetch(@btn, :label) do %><span>{label}</span><% end %>
    </button>
    """
  end

  # Text glyphs — conventional enough that a drawn icon would be worse.
  defp tool_glyph("superscript"), do: "X²"
  defp tool_glyph("subscript"), do: "X₂"
  defp tool_glyph("symbols"), do: "Ω"
  defp tool_glyph("heading"), do: "H"
  defp tool_glyph("markdown"), do: "M"
  defp tool_glyph("html"), do: "<>"

  defp tool_glyph("bold"), do: "B"
  defp tool_glyph("italic"), do: "I"

  # Inline code: bare chevrons. Deliberately distinct from "code-block"
  # below, which frames them — the two used to be near-identical.
  defp tool_glyph("code"),
    do: [
      "M6.28 5.22a.75.75 0 010 1.06L2.56 10l3.72 3.72a.75.75 0 01-1.06 1.06L.97 10.53a.75.75 0 010-1.06l4.25-4.25a.75.75 0 011.06 0zm7.44 0a.75.75 0 011.06 0l4.25 4.25a.75.75 0 010 1.06l-4.25 4.25a.75.75 0 01-1.06-1.06L17.44 10l-3.72-3.72a.75.75 0 010-1.06z"
    ]

  defp tool_glyph("code-block"),
    do: [
      "M4.25 2A2.25 2.25 0 0 0 2 4.25v11.5A2.25 2.25 0 0 0 4.25 18h11.5A2.25 2.25 0 0 0 18 15.75V4.25A2.25 2.25 0 0 0 15.75 2H4.25Zm3.03 5.22a.75.75 0 0 1 0 1.06L5.56 10l1.72 1.72a.75.75 0 1 1-1.06 1.06l-2.25-2.25a.75.75 0 0 1 0-1.06l2.25-2.25a.75.75 0 0 1 1.06 0Zm5.44 0a.75.75 0 0 1 1.06 0l2.25 2.25a.75.75 0 0 1 0 1.06l-2.25 2.25a.75.75 0 1 1-1.06-1.06L14.44 10l-1.72-1.72a.75.75 0 0 1 0-1.06Z"
    ]

  # Task list: two ticks + two lines. The old glyph here was a chevron-left
  # with a bar — an outdent icon that had nothing to do with checkboxes.
  defp tool_glyph("task-list"),
    do: [
      "M2.22 5.03a.75.75 0 0 1 1.06 0l.72.72 1.97-1.97a.75.75 0 1 1 1.06 1.06L4.53 7.34a.75.75 0 0 1-1.06 0L2.22 6.09a.75.75 0 0 1 0-1.06Z",
      "M9.75 5a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5h-7.5Z",
      "M2.22 12.03a.75.75 0 0 1 1.06 0l.72.72 1.97-1.97a.75.75 0 1 1 1.06 1.06l-2.5 2.5a.75.75 0 0 1-1.06 0l-1.25-1.25a.75.75 0 0 1 0-1.06Z",
      "M9.75 12a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5h-7.5Z"
    ]

  # Remove formatting: a backspace, not the bare ✕ it used to be — an ✕
  # reads as "close this menu", not "strip the styling".
  defp tool_glyph("remove-format"),
    do: [
      "M7.22 3.22A.75.75 0 0 1 7.75 3h8.5A2.75 2.75 0 0 1 19 5.75v8.5A2.75 2.75 0 0 1 16.25 17h-8.5a.75.75 0 0 1-.53-.22l-5.5-5.5a1.75 1.75 0 0 1 0-2.47l5.5-5.59Zm3.06 4.28a.75.75 0 0 0-1.06 1.06L10.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L12 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L13.06 10l1.72-1.72a.75.75 0 1 0-1.06-1.06L12 8.94l-1.72-1.72Z"
    ]

  # Blockquote: the conventional bar-plus-lines, instead of the bars-3 that
  # was indistinguishable from the list and indent glyphs.
  defp tool_glyph("blockquote"),
    do: [
      "M3 4a1 1 0 0 1 1-1h.5a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4Z",
      "M8.75 5a.75.75 0 0 0 0 1.5h8.5a.75.75 0 0 0 0-1.5h-8.5Z",
      "M8.75 9.25a.75.75 0 0 0 0 1.5h8.5a.75.75 0 0 0 0-1.5h-8.5Z",
      "M8.75 13.5a.75.75 0 0 0 0 1.5h5.5a.75.75 0 0 0 0-1.5h-5.5Z"
    ]

  # Details / accordion: a framed chevron, so it no longer collides with
  # the bare chevron used by the image-options dropdown.
  defp tool_glyph("details"),
    do: [
      "M4.25 3A2.25 2.25 0 0 0 2 5.25v9.5A2.25 2.25 0 0 0 4.25 17h11.5A2.25 2.25 0 0 0 18 14.75v-9.5A2.25 2.25 0 0 0 15.75 3H4.25Zm2.47 4.97a.75.75 0 0 1 1.06 0L10 10.19l2.22-2.22a.75.75 0 1 1 1.06 1.06l-2.75 2.75a.75.75 0 0 1-1.06 0L6.72 9.03a.75.75 0 0 1 0-1.06Z"
    ]

  defp tool_glyph("horizontal-rule"),
    do: ["M3 10a.75.75 0 0 1 .75-.75h12.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 10Z"]

  # Spoiler: eye-slash reads as "hidden until revealed"; the old filled bar
  # was ambiguous with the horizontal rule.
  defp tool_glyph("spoiler"),
    do: [
      "M3.28 2.22a.75.75 0 0 0-1.06 1.06l14.5 14.5a.75.75 0 1 0 1.06-1.06l-1.745-1.745a10.029 10.029 0 0 0 3.3-4.38 1.651 1.651 0 0 0 0-1.185A10.004 10.004 0 0 0 9.999 3a9.956 9.956 0 0 0-4.744 1.194L3.28 2.22Zm4.472 4.47 1.092 1.092a2.5 2.5 0 0 1 3.374 3.373l1.091 1.092a4 4 0 0 0-5.557-5.557Z",
      "M10.748 13.93l2.523 2.523a9.987 9.987 0 0 1-3.27.547c-4.258 0-7.894-2.66-9.337-6.41a1.651 1.651 0 0 1 0-1.186A10.007 10.007 0 0 1 2.839 6.02L6.07 9.252a4 4 0 0 0 4.678 4.678Z"
    ]

  defp tool_glyph("bullet-list"),
    do: [
      "M6 4.75A.75.75 0 016.75 4h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 4.75zM6 10a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 10zm0 5.25a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75a.75.75 0 01-.75-.75zM1.99 4.75a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 15.25a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 10a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1V10z"
    ]

  defp tool_glyph("ordered-list"),
    do: [
      "M3.0002 1.25C2.58599 1.25 2.2502 1.58579 2.2502 2C2.2502 2.41421 2.58599 2.75 3.0002 2.75H3.2502V5.25C3.2502 5.66421 3.58599 6 4.0002 6C4.41441 6 4.7502 5.66421 4.7502 5.25V2C4.7502 1.58579 4.41441 1.25 4.0002 1.25H3.0002Z",
      "M2.97049 8.65372C3.29513 8.55397 3.64067 8.5 4.0002 8.5C4.16835 8.5 4.33333 8.5118 4.49444 8.53453C4.49127 8.53922 4.48691 8.54312 4.48165 8.54575L2.41479 9.57918C2.1607 9.70622 2.0002 9.96592 2.0002 10.25V11.25C2.0002 11.6642 2.33599 12 2.7502 12H5.2502C5.66441 12 6.0002 11.6642 6.0002 11.25C6.0002 10.8358 5.66441 10.5 5.2502 10.5H3.92725L5.15247 9.88739C5.67202 9.62762 6.0002 9.09661 6.0002 8.51574C6.0002 7.86944 5.57097 7.18897 4.80714 7.06489C4.54401 7.02215 4.27442 7 4.0002 7C3.48967 7 2.99569 7.07676 2.52991 7.21988C2.13397 7.34154 1.91162 7.76115 2.03328 8.15709C2.15494 8.55303 2.57455 8.77538 2.97049 8.65372Z",
      "M7.75 3C7.33579 3 7 3.33579 7 3.75C7 4.16421 7.33579 4.5 7.75 4.5H17.25C17.6642 4.5 18 4.16421 18 3.75C18 3.33579 17.6642 3 17.25 3H7.75Z",
      "M7.75 9.25C7.33579 9.25 7 9.58579 7 10C7 10.4142 7.33579 10.75 7.75 10.75H17.25C17.6642 10.75 18 10.4142 18 10C18 9.58579 17.6642 9.25 17.25 9.25H7.75Z",
      "M7.75 15.5C7.33579 15.5 7 15.8358 7 16.25C7 16.6642 7.33579 17 7.75 17H17.25C17.6642 17 18 16.6642 18 16.25C18 15.8358 17.6642 15.5 17.25 15.5H7.75Z",
      "M2.625 13.875C2.21079 13.875 1.875 14.2108 1.875 14.625C1.875 15.0392 2.21079 15.375 2.625 15.375H4.125C4.19404 15.375 4.25 15.431 4.25 15.5C4.25 15.569 4.19404 15.625 4.125 15.625H3.5C3.08579 15.625 2.75 15.9608 2.75 16.375C2.75 16.7892 3.08579 17.125 3.5 17.125H4.125C4.19404 17.125 4.25 17.181 4.25 17.25C4.25 17.319 4.19404 17.375 4.125 17.375H2.625C2.21079 17.375 1.875 17.7108 1.875 18.125C1.875 18.5392 2.21079 18.875 2.625 18.875H4.125C5.02246 18.875 5.75 18.1475 5.75 17.25C5.75 16.9278 5.65625 16.6276 5.49454 16.375C5.65625 16.1224 5.75 15.8222 5.75 15.5C5.75 14.6025 5.02246 13.875 4.125 13.875H2.625Z"
    ]

  defp tool_glyph("indent"),
    do: [
      "M2 4.75A.75.75 0 0 1 2.75 4h14.5a.75.75 0 0 1 0 1.5H2.75A.75.75 0 0 1 2 4.75Zm6 5A.75.75 0 0 1 8.75 9h8.5a.75.75 0 0 1 0 1.5h-8.5A.75.75 0 0 1 8 9.75Zm-6 5a.75.75 0 0 1 .75-.75h14.5a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1-.75-.75Z",
      "M2.22 8.22a.75.75 0 0 1 1.06 0L5 9.94l-1.72 1.72a.75.75 0 1 1-1.06-1.06l.69-.69-.69-.69a.75.75 0 0 1 0-1Z"
    ]

  defp tool_glyph("outdent"),
    do: [
      "M2 4.75A.75.75 0 0 1 2.75 4h14.5a.75.75 0 0 1 0 1.5H2.75A.75.75 0 0 1 2 4.75Zm6 5A.75.75 0 0 1 8.75 9h8.5a.75.75 0 0 1 0 1.5h-8.5A.75.75 0 0 1 8 9.75Zm-6 5a.75.75 0 0 1 .75-.75h14.5a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1-.75-.75Z",
      "M5.03 8.22a.75.75 0 0 0-1.06 0L2.25 9.94l1.72 1.72a.75.75 0 1 0 1.06-1.06l-.69-.69.69-.69a.75.75 0 0 0 0-1Z"
    ]

  defp tool_glyph("link"),
    do: [
      "M12.232 4.232a2.5 2.5 0 013.536 3.536l-1.225 1.224a.75.75 0 001.061 1.06l1.224-1.224a4 4 0 00-5.656-5.656l-3 3a4 4 0 00.225 5.865.75.75 0 00.977-1.138 2.5 2.5 0 01-.142-3.667l3-3z",
      "M11.603 7.963a.75.75 0 00-.977 1.138 2.5 2.5 0 01.142 3.667l-3 3a2.5 2.5 0 01-3.536-3.536l1.225-1.224a.75.75 0 00-1.061-1.06l-1.224 1.224a4 4 0 105.656 5.656l3-3a4 4 0 00-.225-5.865z"
    ]

  defp tool_glyph("emoji"),
    do: [
      "M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM7 8.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm7-1a1 1 0 1 1-2 0 1 1 0 0 1 2 0Zm-7.536 4.036a.75.75 0 0 1 1.06 0 3.5 3.5 0 0 0 4.95 0 .75.75 0 1 1 1.061 1.06 5 5 0 0 1-7.07 0 .75.75 0 0 1 0-1.06Z"
    ]

  defp tool_glyph("image"),
    do: [
      "M1 5.25A2.25 2.25 0 0 1 3.25 3h13.5A2.25 2.25 0 0 1 19 5.25v9.5A2.25 2.25 0 0 1 16.75 17H3.25A2.25 2.25 0 0 1 1 14.75v-9.5Zm1.5 5.81v3.69c0 .414.336.75.75.75h13.5a.75.75 0 0 0 .75-.75v-2.69l-2.22-2.219a.75.75 0 0 0-1.06 0l-1.91 1.909.47.47a.75.75 0 1 1-1.06 1.06L6.53 8.091a.75.75 0 0 0-1.06 0l-2.97 2.97ZM12 7a1 1 0 1 1 2 0 1 1 0 0 1-2 0Z"
    ]

  defp tool_glyph("video"),
    do: [
      "M3.25 4A2.25 2.25 0 001 6.25v7.5A2.25 2.25 0 003.25 16h7.5A2.25 2.25 0 0013 13.75v-7.5A2.25 2.25 0 0010.75 4h-7.5z",
      "M19 4.75a.75.75 0 0 0-1.28-.53l-3.22 3.22v5.12l3.22 3.22a.75.75 0 0 0 1.28-.53V4.75Z"
    ]

  defp tool_glyph("table"),
    do: [
      "M.99 5.24A2.25 2.25 0 013.25 3h13.5A2.25 2.25 0 0119 5.25v9.5A2.25 2.25 0 0116.75 17H3.25A2.25 2.25 0 011 14.75v-9.5l-.01-.01ZM2.5 7.5V9h5V7.5h-5Zm6.5 0V9h8.5V7.5H9Zm8.5 3H9V12h8.5v-1.5Zm0 3H9V15h7.75a.75.75 0 0 0 .75-.75v-.75Zm-10 1.5V13.5h-5v.75c0 .414.336.75.75.75H7.5Zm-5-3h5V10.5h-5V12Z"
    ]

  defp tool_glyph("callout"),
    do: [
      "M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-7-4a1 1 0 1 1-2 0 1 1 0 0 1 2 0ZM9 9a.75.75 0 0 0 0 1.5h.253a.25.25 0 0 1 .244.304l-.459 2.066A1.75 1.75 0 0 0 10.747 15H11a.75.75 0 0 0 0-1.5h-.253a.25.25 0 0 1-.244-.304l.459-2.066A1.75 1.75 0 0 0 9.253 9H9Z"
    ]

  defp tool_glyph("clipboard"),
    do: [
      "M13.887 3.182c.396.037.79.083 1.183.138C16.194 3.482 17 4.464 17 5.578V16.25A2.75 2.75 0 0 1 14.25 19h-8.5A2.75 2.75 0 0 1 3 16.25V5.578c0-1.114.806-2.096 1.93-2.258.393-.055.787-.101 1.183-.138A3.001 3.001 0 0 1 9 1h2c1.373 0 2.531.923 2.887 2.182ZM7.5 4A1.5 1.5 0 0 1 9 2.5h2A1.5 1.5 0 0 1 12.5 4v.5h-5V4Z"
    ]

  defp tool_glyph("download"),
    do: [
      "M10.75 2.75a.75.75 0 0 0-1.5 0v8.614L6.295 8.235a.75.75 0 1 0-1.09 1.03l4.25 4.5a.75.75 0 0 0 1.09 0l4.25-4.5a.75.75 0 0 0-1.09-1.03l-2.955 3.129V2.75Z",
      "M3.5 12.75a.75.75 0 0 0-1.5 0v2.5A2.75 2.75 0 0 0 4.75 18h10.5A2.75 2.75 0 0 0 18 15.25v-2.5a.75.75 0 0 0-1.5 0v2.5c0 .69-.56 1.25-1.25 1.25H4.75c-.69 0-1.25-.56-1.25-1.25v-2.5Z"
    ]

  defp tool_glyph("fullscreen"),
    do: [
      "M3 4.25A1.25 1.25 0 0 1 4.25 3h3a.75.75 0 0 1 0 1.5h-2.5a.25.25 0 0 0-.25.25v2.5a.75.75 0 0 1-1.5 0v-3Zm10-.5a.75.75 0 0 1 .75-.75h3A1.25 1.25 0 0 1 18 4.25v3a.75.75 0 0 1-1.5 0v-2.5a.25.25 0 0 0-.25-.25h-2.5a.75.75 0 0 1-.75-.75ZM3.75 12.25a.75.75 0 0 1 .75.75v2.5c0 .138.112.25.25.25h2.5a.75.75 0 0 1 0 1.5h-3A1.25 1.25 0 0 1 3 16v-3a.75.75 0 0 1 .75-.75Zm13 0a.75.75 0 0 1 .75.75v3A1.25 1.25 0 0 1 16.25 17h-3a.75.75 0 0 1 0-1.5h2.5a.25.25 0 0 0 .25-.25v-2.5a.75.75 0 0 1 .75-.75Z"
    ]

  defp tool_glyph("eye"),
    do: [
      "M10 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z",
      "M.664 10.59a1.651 1.651 0 0 1 0-1.186A10.004 10.004 0 0 1 10 3c4.257 0 7.893 2.66 9.336 6.41.147.381.146.804 0 1.186A10.004 10.004 0 0 1 10 17c-4.257 0-7.893-2.66-9.336-6.41ZM14 10a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z"
    ]

  defp tool_glyph("sparkles"),
    do: [
      "M15.98 1.804a1 1 0 0 0-1.96 0l-.24 1.192a1 1 0 0 1-.784.785l-1.192.238a1 1 0 0 0 0 1.962l1.192.238a1 1 0 0 1 .785.785l.238 1.192a1 1 0 0 0 1.962 0l.238-1.192a1 1 0 0 1 .785-.785l1.192-.238a1 1 0 0 0 0-1.962l-1.192-.238a1 1 0 0 1-.785-.785l-.238-1.192ZM6.949 5.684a1 1 0 0 0-1.898 0l-.683 2.051a1 1 0 0 1-.633.633l-2.051.683a1 1 0 0 0 0 1.898l2.051.684a1 1 0 0 1 .633.632l.683 2.051a1 1 0 0 0 1.898 0l.683-2.051a1 1 0 0 1 .633-.633l2.051-.683a1 1 0 0 0 0-1.898l-2.051-.683a1 1 0 0 1-.633-.633L6.95 5.684Z"
    ]

  # Every overflow trigger uses the ellipsis — they all mean "more of this
  # section", and the toolbar's section dividers are what distinguish them.
  defp tool_glyph("ellipsis"),
    do: [
      "M3 10a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0Zm5.5 0a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0Zm5.5 0a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0Z"
    ]

  defp tool_glyph("squares-plus"),
    do: [
      "M3.75 3A1.75 1.75 0 0 0 2 4.75v3.5C2 9.216 2.784 10 3.75 10h3.5A1.75 1.75 0 0 0 9 8.25v-3.5A1.75 1.75 0 0 0 7.25 3h-3.5Z",
      "M3.75 11A1.75 1.75 0 0 0 2 12.75v3.5c0 .966.784 1.75 1.75 1.75h3.5A1.75 1.75 0 0 0 9 16.25v-3.5A1.75 1.75 0 0 0 7.25 11h-3.5Z",
      "M12.75 3A1.75 1.75 0 0 0 11 4.75v3.5c0 .966.784 1.75 1.75 1.75h3.5A1.75 1.75 0 0 0 18 8.25v-3.5A1.75 1.75 0 0 0 16.25 3h-3.5Z",
      "M14.5 12.5a.75.75 0 0 0-1.5 0v1.75h-1.75a.75.75 0 0 0 0 1.5H13v1.75a.75.75 0 0 0 1.5 0V15.75h1.75a.75.75 0 0 0 0-1.5H14.5V12.5Z"
    ]

  # Unknown name → an empty slot of the same width, so a row without an
  # icon still lines its label up with the rest.
  defp tool_glyph(_), do: nil

  # -- Events from JS Hook --

  @impl true
  def handle_event("content_changed", %{"markdown" => markdown, "html" => html} = params, socket) do
    sanitized_markdown = sanitize_markdown(markdown, socket.assigns.deny)
    sanitized_html = sanitize_html(html, socket.assigns.deny)

    send(
      self(),
      {:leaf_changed,
       %{
         editor_id: socket.assigns.id,
         markdown: sanitized_markdown,
         html: sanitized_html,
         dirty: Map.get(params, "dirty", true)
       }}
    )

    socket =
      socket
      |> assign(:content, sanitized_markdown)
      |> assign(:visual_html, sanitized_html)

    # If a denied element was stripped from the HTML, push the clean version
    # back to the client so the hybrid contenteditable doesn't keep showing it.
    socket =
      if sanitized_html != html do
        push_event(socket, "leaf-set-html:#{socket.assigns.id}", %{html: sanitized_html})
      else
        socket
      end

    {:noreply, socket}
  end

  # Reply to an explicit `send_update(action: :flush, ref: …)`. Pushed by
  # the client right after the matching content event, so the host's
  # `{:leaf_changed, …}` has already landed and this only has to say
  # "that one was yours". No ref, no message — see the "Flushing" section.
  def handle_event("flushed", %{"ref" => ref} = params, socket) do
    markdown = sanitize_markdown(Map.get(params, "markdown", ""), socket.assigns.deny)
    html = sanitize_html(Map.get(params, "html", ""), socket.assigns.deny)

    send(
      self(),
      {:leaf_flushed,
       %{
         editor_id: socket.assigns.id,
         ref: ref,
         markdown: markdown,
         html: html
       }}
    )

    {:noreply, socket}
  end

  # Double-clicking an atomic preserved block opens a raw-source editor for
  # just that block. On save the client sends the new source here so the
  # preview (attributes, thumbnail, rendered children) can be rebuilt by
  # the same code that built it on first render — the client has no
  # markdown renderer of its own.
  def handle_event("render_preserved", %{"raw" => raw, "token" => token}, socket) do
    {:noreply,
     push_event(socket, "leaf-preserved-html:#{socket.assigns.id}", %{
       token: token,
       html: preserved_chip(raw, :block)
     })}
  end

  def handle_event("markdown_content_changed", %{"content" => content} = params, socket) do
    sanitized_markdown = sanitize_markdown(content, socket.assigns.deny)

    html =
      sanitized_markdown
      |> markdown_to_html(render_opts(socket))
      |> sanitize_html(socket.assigns.deny)

    send(
      self(),
      {:leaf_changed,
       %{
         editor_id: socket.assigns.id,
         markdown: sanitized_markdown,
         html: html,
         dirty: Map.get(params, "dirty", true)
       }}
    )

    {:noreply, assign(socket, :content, sanitized_markdown)}
  end

  def handle_event("mode_changed", %{"mode" => mode} = params, socket) do
    mode_atom = String.to_existing_atom(mode)
    deny = Map.get(socket.assigns, :deny, [])
    mode_atom = normalize_mode(mode_atom, deny)
    content = Map.get(params, "content", socket.assigns.content)

    send(
      self(),
      {:leaf_mode_changed,
       %{
         editor_id: socket.assigns.id,
         mode: mode_atom
       }}
    )

    {:noreply, socket |> assign(:mode, mode_atom) |> assign(:content, content)}
  end

  # One splice against the state the host last heard about. `remove` characters
  # at `at` are replaced by `insert`.
  #
  # This is the operation-shaped counterpart to `content_changed`, which stays
  # exactly as it was — a host that wants snapshots is unaffected. `base_length`
  # is the length of the text the splice applies to, so a host holding a
  # document of a different length can tell it has diverged instead of applying
  # an offset that no longer means what it meant.
  def handle_event("operation", %{"at" => at, "remove" => remove} = params, socket)
      when is_integer(at) and is_integer(remove) do
    send(
      self(),
      {:leaf_operation,
       %{
         editor_id: socket.assigns.id,
         at: at,
         remove: remove,
         insert: to_string(Map.get(params, "insert", "")),
         seq: Map.get(params, "seq"),
         base_length: Map.get(params, "base_length")
       }}
    )

    {:noreply, socket}
  end

  # The client has found `[[…]]` targets it has no answer for yet. Only the host
  # knows which notes exist, so it does the resolving and replies with
  # `action: :link_targets`.
  def handle_event("resolve_links", %{"targets" => targets} = params, socket)
      when is_list(targets) do
    send(
      self(),
      {:leaf_resolve_links,
       %{
         editor_id: socket.assigns.id,
         targets: Enum.filter(targets, &is_binary/1),
         seq: Map.get(params, "seq")
       }}
    )

    {:noreply, socket}
  end

  # A wiki link was clicked. Leaf does not navigate: where a target lives is the
  # host's question, and it may want a modal, a new tab or a "create this note"
  # flow instead of a plain navigation.
  def handle_event("link_clicked", %{"target" => target} = params, socket)
      when is_binary(target) do
    send(
      self(),
      {:leaf_link_clicked,
       %{
         editor_id: socket.assigns.id,
         target: target,
         heading: params["heading"],
         href: params["href"]
       }}
    )

    {:noreply, socket}
  end

  def handle_event("suggest", %{"trigger" => trigger, "query" => query} = params, socket) do
    send(
      self(),
      {:leaf_suggest,
       %{
         editor_id: socket.assigns.id,
         trigger: trigger,
         query: query,
         seq: Map.get(params, "seq")
       }}
    )

    {:noreply, socket}
  end

  def handle_event("insert_request", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)

    send(
      self(),
      {:leaf_insert_request,
       %{
         editor_id: socket.assigns.id,
         type: type_atom
       }}
    )

    {:noreply, socket}
  end

  def handle_event("html_content_changed", %{"content" => html} = params, socket) do
    sanitized_html = sanitize_html(html, socket.assigns.deny)

    send(
      self(),
      {:leaf_changed,
       %{
         editor_id: socket.assigns.id,
         markdown: socket.assigns.content,
         html: sanitized_html,
         dirty: Map.get(params, "dirty", true)
       }}
    )

    {:noreply, assign(socket, :visual_html, sanitized_html)}
  end

  def handle_event("sync_markdown_to_visual", %{"markdown" => markdown}, socket) do
    html =
      markdown
      |> sanitize_markdown(socket.assigns.deny)
      |> markdown_to_html(render_opts(socket))
      |> sanitize_html(socket.assigns.deny)

    {:noreply, push_event(socket, "leaf-set-html:#{socket.assigns.id}", %{html: html})}
  end

  def handle_event("sync_html_to_visual", %{"html" => html}, socket) do
    sanitized_html = sanitize_html(html, socket.assigns.deny)

    {:noreply, push_event(socket, "leaf-set-html:#{socket.assigns.id}", %{html: sanitized_html})}
  end

  def handle_event("convert_markdown_to_html", %{"markdown" => markdown}, socket) do
    html =
      markdown
      |> sanitize_markdown(socket.assigns.deny)
      |> markdown_to_html()
      |> sanitize_html(socket.assigns.deny)

    {:noreply, push_event(socket, "leaf-set-html-textarea:#{socket.assigns.id}", %{html: html})}
  end

  def handle_event("focus", _params, socket) do
    send(self(), {:leaf_focus, %{editor_id: socket.assigns.id}})
    {:noreply, socket}
  end

  def handle_event("blur", _params, socket) do
    send(self(), {:leaf_blur, %{editor_id: socket.assigns.id}})
    {:noreply, socket}
  end

  def handle_event("selection_changed", params, socket) do
    send(
      self(),
      {:leaf_selection_changed,
       %{
         editor_id: socket.assigns.id,
         text: Map.get(params, "text", ""),
         range: Map.get(params, "range")
       }}
    )

    {:noreply, socket}
  end

  def handle_event("paste_image", params, socket) do
    send(
      self(),
      {:leaf_paste_image,
       %{
         editor_id: socket.assigns.id,
         data_url: Map.get(params, "data_url"),
         name: Map.get(params, "name"),
         mime: Map.get(params, "mime")
       }}
    )

    {:noreply, socket}
  end

  def handle_event("toolbar_action", %{"id" => id} = params, socket) do
    send(
      self(),
      {:leaf_toolbar_action,
       %{
         editor_id: socket.assigns.id,
         id: id,
         selection: %{
           text: Map.get(params, "text", ""),
           range: Map.get(params, "range")
         }
       }}
    )

    {:noreply, socket}
  end

  # The image-URL dialog (and other media popovers) push these to signal the
  # server that a modal UI is active. Currently no-op on the server side —
  # they exist so a future hook can react (suspend autosave, freeze the
  # component, etc.) without the LiveView crashing on an unmatched event.
  def handle_event("media_ui_opened", _params, socket), do: {:noreply, socket}
  def handle_event("media_ui_closed", _params, socket), do: {:noreply, socket}

  # -- Inline suggestions --

  @default_suggestion_token "[\\p{L}\\p{N}_-]"
  @suggestion_boundaries ~w(word_start line_start not_line_start any)

  @doc false
  # Turn the host's `suggestions` list into the flat string map the template
  # writes out as data attributes. Everything is optional but `:trigger`;
  # entries without one are dropped rather than shipped half-configured.
  #
  # Keys may be atoms or strings, and `:token` / `:first_char` accept either a
  # `Regex` (whose source is extracted) or a raw character-class string, so
  # `token: ~r/[\p{L}\p{N}_-]/u` and `token: "[a-z]"` both work.
  def normalized_suggestions(list) when is_list(list) do
    list
    |> Enum.map(&normalize_suggestion/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalized_suggestions(_), do: []

  defp normalize_suggestion(spec) when is_map(spec) do
    case to_string(efetch(spec, :trigger) || "") do
      "" ->
        nil

      trigger ->
        %{
          trigger: trigger,
          boundary: suggestion_boundary(efetch(spec, :boundary)),
          token: char_class(efetch(spec, :token), @default_suggestion_token),
          first_char: char_class(efetch(spec, :first_char), nil),
          min_chars: non_neg_int(efetch(spec, :min_chars), 0),
          max_length: non_neg_int(efetch(spec, :max_length), 0),
          debounce: non_neg_int(efetch(spec, :debounce), 150),
          max_results: non_neg_int(efetch(spec, :max_results), 10),
          allow_create: to_string(efetch(spec, :allow_create) == true),
          keep_trigger: to_string(efetch(spec, :keep_trigger) != false),
          insert_suffix: suggestion_suffix(efetch(spec, :insert_suffix)),
          label: to_string(efetch(spec, :label) || ""),
          exclude: suggestion_exclusions(efetch(spec, :exclude))
        }
    end
  end

  defp normalize_suggestion(_), do: nil

  defp suggestion_boundary(nil), do: "word_start"

  defp suggestion_boundary(value) do
    string = to_string(value)
    if string in @suggestion_boundaries, do: string, else: "word_start"
  end

  # `nil` means "not configured"; an explicit "" means "no suffix".
  defp suggestion_suffix(nil), do: " "
  defp suggestion_suffix(value), do: to_string(value)

  # Default exclusions match what a markdown parser would ignore anyway:
  # fenced/inline code and markdown link/image destinations. URL fragments
  # (`…/page#section`) are already excluded by the `:word_start` boundary.
  defp suggestion_exclusions(nil), do: "code,link"

  defp suggestion_exclusions(list) when is_list(list),
    do: Enum.map_join(list, ",", &to_string/1)

  defp suggestion_exclusions(value), do: to_string(value)

  defp char_class(nil, default), do: default
  defp char_class(%Regex{} = regex, _default), do: Regex.source(regex)
  defp char_class(value, _default) when is_binary(value), do: value
  defp char_class(_, default), do: default

  defp non_neg_int(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_neg_int(_, default), do: default

  # Host replies may be plain strings (`["elixir"]`) or maps with any mix of
  # atom/string keys. Normalize to the shape the client renders, dropping
  # anything without a usable value.
  defp normalize_suggestion_results(results) when is_list(results) do
    results
    |> Enum.map(&normalize_suggestion_result/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_suggestion_results(_), do: []

  defp normalize_suggestion_result(value) when is_binary(value) do
    %{value: value, label: value, sublabel: "", icon: ""}
  end

  defp normalize_suggestion_result(result) when is_map(result) do
    value = efetch(result, :value) || efetch(result, :label)

    case value && to_string(value) do
      nil ->
        nil

      "" ->
        nil

      value ->
        %{
          value: value,
          label: to_string(efetch(result, :label) || value),
          sublabel: to_string(efetch(result, :sublabel) || ""),
          icon: to_string(efetch(result, :icon) || "")
        }
    end
  end

  defp normalize_suggestion_result(_), do: nil

  # -- Helpers --

  defp preserve_tags(socket), do: Map.get(socket.assigns, :preserve_tags, [])

  # Fetch a key from a host-supplied map, tolerating either atom or string
  # keys (so `%{id: "hero"}` and `%{"id" => "hero"}` both work).
  defp efetch(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  # Per-instance gettext: render/1 stashes the editor's `gettext_backend`
  # assign in the process dictionary (render runs synchronously in the
  # LiveView process), so the bare `t(...)` calls in the template pick it
  # up without threading the backend through every call site. Falls back to
  # the app-global config, then to the untranslated string.
  #
  # Lookups try the `"leaf"` domain first (what the shipped
  # `priv/gettext/leaf.pot` merges into) and fall back to `"default"` for
  # hosts that would rather keep everything in one catalog. Gettext returns
  # the msgid unchanged when there is no translation, which is exactly the
  # signal for "try the other domain".
  defp t(string) do
    backend =
      Process.get(:leaf_gettext_backend) ||
        Application.get_env(:leaf, :gettext_backend)

    case backend do
      nil ->
        string

      backend ->
        case Gettext.dgettext(backend, "leaf", string) do
          ^string -> Gettext.gettext(backend, string)
          translated -> translated
        end
    end
  end

  @bundled_random_loading_presets [
    :unpuzzling,
    :brewing,
    :polishing,
    :composing,
    :crafting,
    :tidying
  ]

  defp loading_preset_text(:default), do: "Loading…"
  defp loading_preset_text(:unpuzzling), do: "Unpuzzling…"
  defp loading_preset_text(:brewing), do: "Brewing…"
  defp loading_preset_text(:polishing), do: "Polishing…"
  defp loading_preset_text(:composing), do: "Composing…"
  defp loading_preset_text(:crafting), do: "Crafting…"
  defp loading_preset_text(:tidying), do: "Tidying…"

  defp resolve_loading_preset(:random), do: Enum.random(@bundled_random_loading_presets)
  defp resolve_loading_preset(other), do: other

  # Inline <style> tag for the loading state. HEEx treats <style> bodies as
  # opaque text, so we build the tag as a safe HTML iolist outside the
  # template and let the {...} interpolation dump it.
  defp loading_state_style_tag(height, nonce) do
    nonce_str = nonce |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    raw([
      ~s(<style nonce="),
      nonce_str,
      ~s(">),
      loading_state_css(height),
      ~s(</style>)
    ])
  end

  # Bundle-presence check. Leaf does not bundle its JS into the host, and
  # an editor whose hook never attached is indistinguishable from a working
  # one at a glance — it renders, it looks ordinary, it silently captures
  # nothing. This is the only place the check can live: if the bundle is
  # absent there is no Leaf JS around to notice its own absence.
  #
  # Guarded so exactly one timer runs per page however many editors are on
  # it, and it only ever writes to the console. Hosts under a CSP that
  # forbids inline scripts and cannot pass a `script_nonce` turn it off
  # with `bundle_check={false}` — it is a diagnostic, nothing depends on it.
  defp bundle_check_script_tag(nonce) do
    nonce_str = nonce |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    raw([
      ~s(<script nonce="),
      nonce_str,
      ~s(">),
      bundle_check_js(),
      ~s(</script>)
    ])
  end

  defp bundle_check_js do
    """
    (function(){
      if (window.__leafBundleCheck) return;
      window.__leafBundleCheck = 1;
      setTimeout(function(){
        var stuck = document.querySelector('[phx-hook="Leaf"][data-leaf-mount-state="loading"]');
        if (!stuck) return;
        var missing = !(window.LeafHooks && window.LeafHooks.Leaf);
        console.error(
          '[leaf] editor "' + (stuck.id || '?') + '" never attached its JS hook, so it ' +
          'captures nothing you type. ' +
          (missing
            ? 'window.LeafHooks.Leaf is not defined: leaf.js was never loaded.'
            : 'leaf.js IS loaded, so the hook is most likely not registered with the LiveSocket.') +
          '\\n  1. import "../../../deps/leaf/priv/static/assets/leaf.js" in app.js' +
          '\\n  2. spread window.LeafHooks into the LiveSocket `hooks` option' +
          '\\n  3. check that the LiveView connected at all (earlier console errors)' +
          '\\nSee the "JS Setup" section of the Leaf docs.'
        );
      }, 5000);
    })();
    """
  end

  # Inline CSS for the loading state. Emitted once per editor at the top of
  # render/1 so it applies on first paint, before the JS hook injects the
  # full editor stylesheet in mounted().
  defp loading_state_css(height) do
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

  # Empty content still emits a `<p><br></p>` paragraph so the
  # contenteditable starts with the right block wrapper on first paint —
  # without it, the user can click in and start typing before the JS
  # hook's `mounted()` callback runs the same fixup, and their first
  # characters end up as bare text inside the editor div (no `<p>`).
  # That breaks the hybrid auto-format helpers (`_maybeAutoFormatHeading`
  # & co.) which require the current block to be a `<p>`.
  # 2-arity variant: when `preserve_tags` is non-empty, custom/unknown tags
  # (e.g. <Hero/>, <CTA/>) are pulled out of the markdown BEFORE MDEx
  # (which would otherwise mangle their form), rendered as atomic,
  # non-editable placeholder blocks, and restored verbatim. The client
  # serializes those placeholders straight back to their original source,
  # so custom XML round-trips byte-for-byte through visual/hybrid mode.
  defp markdown_to_html(markdown, opts) when is_binary(markdown) and is_map(opts) do
    preserve = Map.get(opts, :preserve_tags, [])

    html =
      if preserve == [] do
        markdown_to_html(markdown)
      else
        {protected, store} = extract_preserved_tags(markdown, preserve)

        protected
        |> markdown_to_html()
        |> restore_preserved_tags(store)
      end

    html = if Map.get(opts, :hashtags, false), do: decorate_hashtags(html), else: html
    if Map.get(opts, :wiki_links, false), do: decorate_wiki_links(html), else: html
  end

  # The per-render knobs the markdown→HTML pass needs, read off the
  # component's own assigns rather than threaded through every call site.
  defp render_opts(socket) do
    %{
      preserve_tags: preserve_tags(socket),
      hashtags:
        socket.assigns
        |> Map.get(:suggestions, [])
        |> normalized_suggestions()
        |> hashtag_trigger?(),
      wiki_links: wiki_links_enabled?(socket.assigns[:wiki_links])
    }
  end

  # `[[…]]` is only a link if the host said so. Without the opt-in, the
  # brackets are left as literal text — a document using them for something
  # else should not sprout links.
  #
  # Decorating and RESOLVING are separate capabilities. A host that only wants
  # the brackets to read as links — a viewer, or one whose targets are known to
  # exist — sets `resolve: false` and is never asked to answer anything. Tying
  # the two together would have made "render these as links" impossible without
  # also implementing a resolver.
  defp wiki_links_enabled?(nil), do: false
  defp wiki_links_enabled?(false), do: false
  defp wiki_links_enabled?(_), do: true

  defp collab_operations?(%{} = config), do: Map.get(config, :operations, false) == true
  defp collab_operations?(true), do: true
  defp collab_operations?(_), do: false

  defp wiki_links_resolve?(%{} = config), do: Map.get(config, :resolve, true) != false
  defp wiki_links_resolve?(other), do: wiki_links_enabled?(other)

  # How a link is followed. `:modifier` (the default) keeps a bare click for the
  # caret while editing; `:click` suits a surface where nothing competes for it.
  # A host knows which its editor is; Leaf should not assume.
  defp wiki_links_follow(%{} = config), do: to_string(Map.get(config, :follow, :modifier))
  defp wiki_links_follow(_), do: "modifier"

  # `#` is only a tag sigil if the host said so by configuring a `#`
  # suggestion trigger. Without that, `#` is left alone — a document using
  # it for issue numbers or CSS ids should not sprout tag chips.
  defp hashtag_trigger?(suggest_configs) when is_list(suggest_configs) do
    Enum.any?(suggest_configs, &(Map.get(&1, :trigger) == "#"))
  end

  defp hashtag_trigger?(_), do: false

  # `%{"target" => %{href: …, exists: bool}}`, tolerant of string or atom keys
  # and of a bare href string, so a host can answer in whichever shape is
  # natural without the client having to guess.
  defp normalize_link_targets(targets) when is_map(targets) do
    Map.new(targets, fn {target, info} ->
      {to_string(target), normalize_link_target(info)}
    end)
  end

  defp normalize_link_targets(_), do: %{}

  defp normalize_link_target(%{} = info) do
    href = Map.get(info, :href) || Map.get(info, "href")

    title = Map.get(info, :title) || Map.get(info, "title")

    %{
      href: if(is_binary(href), do: href, else: nil),
      exists: Map.get(info, :exists, Map.get(info, "exists", is_binary(href))) == true,
      # Optional tooltip. Leaf ships no wording of its own for this: a label
      # like "Not found" is the host's to write, in the host's language, about
      # the host's own idea of what a target is.
      title: if(is_binary(title), do: title, else: nil)
    }
  end

  defp normalize_link_target(href) when is_binary(href),
    do: %{href: href, exists: true, title: nil}

  defp normalize_link_target(_), do: %{href: nil, exists: false, title: nil}

  # Replace each occurrence of a preserved tag with an inert text token,
  # returning {protected_markdown, %{token => original_source}}.
  defp extract_preserved_tags(markdown, preserve_tags) do
    matches =
      preserve_tags
      |> Enum.flat_map(fn tag ->
        t = Regex.escape(to_string(tag))
        {:ok, re} = Regex.compile("<#{t}\\b[^>]*?/>|<#{t}\\b[^>]*?>.*?</#{t}>", "is")
        re |> Regex.scan(markdown) |> Enum.map(&hd/1)
      end)
      |> Enum.uniq()

    matches
    |> Enum.with_index()
    |> Enum.reduce({markdown, %{}}, fn {match, i}, {md, store} ->
      token = "LEAFPRESERVED#{i}LEAFEND"
      {String.replace(md, match, token), Map.put(store, token, match)}
    end)
  end

  # Swap tokens back for atomic placeholder spans carrying the verbatim
  # source in a `data-leaf-raw` attribute. A standalone token that MDEx
  # wrapped in its own `<p>` becomes the taller block chip; an inline token
  # stays a compact inline one.
  defp restore_preserved_tags(html, store) do
    Enum.reduce(store, html, fn {token, raw}, acc ->
      acc
      |> String.replace("<p>#{token}</p>", "<p>#{preserved_chip(raw, :block)}</p>")
      |> String.replace(token, preserved_chip(raw, :inline))
    end)
  end

  # Render one preserved custom tag as an atomic block.
  #
  # The block is `contenteditable="false"` and carries the verbatim source
  # in `data-leaf-raw` — that attribute, not the rendered preview, is what
  # the client serializes back, so everything below is free to be as rich
  # as it likes without any risk to the round trip.
  #
  # What it renders is a *preview of the component*, not its source. A
  # writer scanning their own document needs to know which component this
  # is and roughly what it will say; `title="…" subtitle="…"` in monospace
  # answers neither question without being read like code. So known
  # attribute names are mapped to typographic roles — title, subtitle,
  # eyebrow, media, call-to-action — and typeset in the editor's own prose
  # voice. Only the attributes with no role left over are shown as source,
  # small and faint, because for those there is nothing better to say.
  #
  # The scale is deliberately restrained: this is a placeholder that reads
  # like prose, not an imitation of the published component. A document
  # with four Heroes still has to be readable, and Leaf has no idea what
  # the host's Hero actually looks like.
  #
  # Every child element is phrasing content, because the block form still
  # sits inside the `<p>` MDEx produced.
  defp preserved_chip(raw, layout) do
    {name, attrs, inner} = parse_preserved_tag(raw)
    roles = attribute_roles(attrs)

    body =
      case layout do
        :inline -> inline_chip_body(name, roles, inner)
        :block -> block_chip_body(name, roles, inner)
      end

    # `has-media` lets the stylesheet know the nameplate is sitting over a
    # banner rather than over the first line of text, so only the text case
    # needs to reserve room for it.
    classes =
      case layout do
        :inline -> "leaf-atomic leaf-atomic-inline"
        :block when roles.media != "" -> "leaf-atomic leaf-atomic-block leaf-atomic-has-media"
        :block -> "leaf-atomic leaf-atomic-block"
      end

    ~s(<span class="#{classes}" contenteditable="false" data-leaf-raw="#{escape_attr(raw)}") <>
      ~s( data-leaf-tag="#{escape_attr(name)}" title="#{escape_attr(preserved_tooltip(raw))}">) <>
      body <> ~s(</span>)
  end

  # The nameplate sits in the top-RIGHT corner, which is the one structural
  # choice here worth defending: it hands the primary reading position —
  # top-left, where the eye lands — to the writer's own content, and puts
  # the machine fact where it can be found but not tripped over.
  defp block_chip_body(name, roles, inner) do
    preview =
      [
        role_span(roles.eyebrow, "leaf-atomic-eyebrow"),
        role_span(roles.title, "leaf-atomic-title"),
        role_span(roles.subtitle, "leaf-atomic-subtitle"),
        preserved_inner_preview(inner),
        chip_cta(roles),
        chip_rest_attrs(roles.rest)
      ]
      |> Enum.reject(&(&1 == ""))

    nameplate = ~s(<span class="leaf-atomic-name">#{escape_text(name)}</span>)
    hint = ~s(<span class="leaf-atomic-hint">#{escape_text(t("Double-click to edit"))}</span>)
    media = chip_media(roles.media)

    # A tag with nothing to show (`<Divider />`) collapses to the nameplate
    # rather than opening an empty box.
    content =
      if preview == [] and media == "" do
        ""
      else
        media <> ~s(<span class="leaf-atomic-preview">#{Enum.join(preview)}</span>)
      end

    nameplate <> hint <> content
  end

  # Inline tags interrupt a sentence, so they stay the size of a word: the
  # tag name plus whichever single value best identifies *which* one it is.
  # A bare `<Image>` in the middle of a paragraph is worse than useless —
  # every one of them looks the same — so the fallback chain runs all the
  # way down to a filename before it gives up.
  defp inline_chip_body(name, roles, inner) do
    value =
      [
        roles.title,
        roles.subtitle,
        roles.cta_label,
        String.trim(inner),
        file_label(roles.media),
        file_label(roles.source),
        roles.link
      ]
      |> Enum.find("", &(&1 not in ["", nil]))
      |> truncate(40)

    ~s(<span class="leaf-atomic-name">#{escape_text(name)}</span>) <>
      if value == "",
        do: "",
        else: ~s(<span class="leaf-atomic-value">#{escape_text(value)}</span>)
  end

  defp role_span("", _class), do: ""

  defp role_span(value, class) do
    ~s(<span class="#{class}">#{escape_text(truncate(value, 240))}</span>)
  end

  defp chip_media(""), do: ""

  defp chip_media(url) do
    ~s(<img class="leaf-atomic-media" src="#{escape_attr(url)}" alt="" loading="lazy">)
  end

  # A label with a destination is a button on the published page, so it
  # previews as one. The destination rides along, muted — knowing where a
  # CTA points is usually the thing you came to check.
  defp chip_cta(%{cta_label: "", link: ""}), do: ""

  defp chip_cta(%{cta_label: label, link: link}) do
    text = if label == "", do: link, else: label

    ~s(<span class="leaf-atomic-cta"><span class="leaf-atomic-cta-label">) <>
      escape_text(truncate(text, 60)) <>
      ~s(</span>) <>
      if(link == "" or label == "",
        do: "",
        else: ~s(<span class="leaf-atomic-cta-link">#{escape_text(truncate(link, 60))}</span>)
      ) <>
      ~s(</span>)
  end

  defp chip_rest_attrs([]), do: ""

  defp chip_rest_attrs(attrs) do
    text =
      attrs
      |> Enum.take(6)
      |> Enum.map_join(" ", fn {k, v} -> ~s(#{k}="#{truncate(v, 32)}") end)

    ~s(<span class="leaf-atomic-rest">#{escape_text(text)}</span>)
  end

  @preserved_attr_re ~r/([A-Za-z_:][\w.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/

  # {tag_name, [{attr, value}], inner_source}. Only the OPENING tag is
  # scanned for attributes — attributes on nested tags belong to those.
  defp parse_preserved_tag(raw) do
    name =
      case Regex.run(~r/<\s*([A-Za-z][\w.-]*)/, raw) do
        [_, n] -> n
        _ -> "block"
      end

    open_tag =
      case Regex.run(~r/^\s*<[^>]*>/s, raw) do
        [tag] -> tag
        _ -> raw
      end

    attrs =
      @preserved_attr_re
      |> Regex.scan(open_tag)
      |> Enum.map(fn
        [_, key, dq, "", ""] -> {key, dq}
        [_, key, "", sq, ""] -> {key, sq}
        [_, key, "", "", bare] -> {key, bare}
        [_, key | rest] -> {key, Enum.find(rest, "", &(&1 != ""))}
      end)

    inner =
      case Regex.run(~r/^\s*<[^>]*[^\/]>(.*)<\/[A-Za-z][\w.-]*\s*>\s*$/s, raw) do
        [_, body] -> body
        _ -> ""
      end

    {name, attrs, inner}
  end

  # Attribute names mapped to the role they play in the preview. Hosts name
  # things variously, so each role takes the common synonyms; the first
  # match on the tag wins.
  #
  # There is no schema to consult — Leaf has never seen the host's `<Hero>`
  # — so this is a convention, not a contract. Getting it wrong costs
  # nothing: an unrecognised attribute falls through to the source line at
  # the bottom, which is exactly where it was before.
  @role_title ~w(title heading headline name)
  @role_eyebrow ~w(kicker eyebrow overline badge category)
  # `alt` earns a role because on a media component it is usually the only
  # human-written thing on the tag.
  @role_subtitle ~w(subtitle subheading tagline description summary caption blurb text body alt)
  @role_link ~w(href url link to)
  @role_cta ~w(label cta button action)

  # These name a picture outright, so any URL-ish value is taken at face
  # value — real image URLs routinely have no extension (CDN paths, signed
  # URLs, `placehold.co/200x80/png`), and demanding one means most real
  # content gets no thumbnail.
  @preserved_image_attrs ~w(image img poster thumbnail thumb cover background bg avatar photo banner)
  # `src` is ambiguous — `<Audio src="…mp3">` uses it too — so it has to
  # actually look like an image before we draw one.
  @preserved_src_attrs ~w(src)
  @url_ref_re ~r{^(?:https?://|/|\./|data:)\S*$}i
  @image_ref_re ~r{^(?:data:image/|.*\.(?:png|jpe?g|gif|webp|avif|svg)(?:[?#]|$))}i

  # Sort a tag's attributes into display roles, keeping whatever is left
  # over so nothing is silently dropped.
  defp attribute_roles(attrs) do
    media = Enum.find_value(attrs, "", fn attr -> if image_attr?(attr), do: elem(attr, 1) end)
    link = take_role(attrs, @role_link)
    cta = take_role(attrs, @role_cta)

    # `label` is a title on its own and a button caption next to a
    # destination — the same word doing two jobs, disambiguated by whether
    # there is anywhere to go.
    {title, cta_label} =
      case {take_role(attrs, @role_title), cta, link} do
        {"", label, ""} -> {label, ""}
        {"", label, _link} -> {"", label}
        {title, label, _} -> {title, label}
      end

    claimed =
      [
        title,
        cta_label,
        link,
        media,
        take_role(attrs, @role_eyebrow),
        take_role(attrs, @role_subtitle)
      ]
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    %{
      title: title,
      eyebrow: take_role(attrs, @role_eyebrow),
      subtitle: take_role(attrs, @role_subtitle),
      media: media,
      # Any source-ish attribute, URL-shaped or not. Never drawn as a
      # picture — it exists so an inline chip can fall back to a filename
      # rather than render as a bare tag name.
      source: take_role(attrs, @preserved_image_attrs ++ @preserved_src_attrs),
      link: link,
      cta_label: cta_label,
      rest: Enum.reject(attrs, fn {_k, v} -> v in claimed end)
    }
  end

  defp take_role(attrs, names) do
    Enum.find_value(attrs, "", fn {k, v} ->
      if String.downcase(k) in names and String.trim(v) != "", do: v
    end)
  end

  defp image_attr?({key, value}) do
    key = String.downcase(key)

    cond do
      not Regex.match?(@url_ref_re, value) -> false
      key in @preserved_image_attrs -> true
      key in @preserved_src_attrs -> Regex.match?(@image_ref_re, value)
      true -> false
    end
  end

  # The last path segment of a URL — the only part of `https://cdn…/a/b/
  # hero-2x.png?v=3` a person actually reads.
  defp file_label(""), do: ""

  defp file_label(url) do
    url
    |> String.split(["?", "#"])
    |> hd()
    |> String.split("/")
    |> List.last()
    |> Kernel.||("")
  end

  defp preserved_inner_preview(inner) do
    case String.trim(inner) do
      "" -> ""
      trimmed -> ~s(<span class="leaf-atomic-body">#{render_inner_markdown(trimmed)}</span>)
    end
  end

  # A preserved tag's children rendered as formatted text — this is what
  # makes the bold, the links and the images inside `<Header>…</Header>`
  # visible while writing.
  #
  # Two deliberate restrictions. `unsafe: false` means raw HTML in the
  # children is dropped rather than injected, so a nested custom tag can't
  # recurse back into the chip machinery or smuggle markup into the
  # preview. And the `<p>` wrappers are unwrapped because the block chip
  # is phrasing content living inside MDEx's own `<p>` — a nested `<p>`
  # would close it and split the chip in half.
  defp render_inner_markdown(source) do
    case MDEx.to_html(source, render: [hardbreaks: true, unsafe: false]) do
      {:ok, html} ->
        html
        |> String.replace(~r{<!--\s*raw HTML omitted\s*-->}i, "")
        |> String.replace(~r{</p>\s*<p>}, "<br>")
        |> String.replace(~r{^\s*<p>|</p>\s*$}, "")
        # The chip is not editable, but a real `href` inside a
        # contenteditable is still a live target for ctrl-click and drag.
        # Keep the look, drop the destination.
        |> String.replace(~r/<a\s+href=/i, ~s(<a data-leaf-href=))
        |> String.trim()

      {:error, _} ->
        escape_text(source)
    end
  end

  defp preserved_tooltip(raw) do
    truncate(String.replace(raw, ~r/\s+/, " "), 200)
  end

  defp truncate(value, max) do
    string = to_string(value)

    if String.length(string) > max do
      String.slice(string, 0, max - 1) <> "…"
    else
      string
    end
  end

  defp escape_attr(value) do
    value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp escape_text(value), do: escape_attr(value)

  defp markdown_to_html(nil), do: "<p><br></p>"
  defp markdown_to_html(""), do: "<p><br></p>"

  defp markdown_to_html(markdown) do
    case MDEx.to_html(markdown, render: [hardbreaks: true, unsafe: true]) do
      {:ok, html} ->
        clean_html(html)

      {:error, _} ->
        "<p>" <> Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(markdown)) <> "</p>"
    end
  end

  # MDEx/comrak occasionally adds newlines inside inline elements; collapse
  # those so HTML mode shows clean single-line tags.
  defp clean_html(html) do
    html
    |> String.replace(~r/<(h[1-6]|p|li|blockquote|a)([^>]*)>\n/, "<\\1\\2>")
    |> String.replace(~r/\s*<\/(h[1-6]|p|li|blockquote|a)>/, "</\\1>")
    |> unwrap_loose_list_items()
    |> apply_task_lists()
    |> apply_callouts()
    |> apply_spoiler_syntax()
    |> String.trim()
  end

  # GFM callouts: `> [!NOTE]` etc. MDEx/comrak leaves `[!NOTE]` as literal text
  # at the start of the blockquote's first paragraph. Promote the blockquote
  # to a styled callout with a derived (non-editable) title label; the client
  # serializes it back to `> [!NOTE]`.
  defp apply_callouts(html) do
    Regex.replace(
      ~r/<blockquote>\s*<p>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(?:<br\s*\/?>)?\s*/i,
      html,
      fn _full, type ->
        lower = String.downcase(type)
        title = String.capitalize(lower)

        ~s(<blockquote class="leaf-callout leaf-callout-#{lower}" data-callout="#{lower}"><p class="leaf-callout-title" contenteditable="false">#{title}</p><p>)
      end
    )
  end

  # GFM task lists: MDEx/comrak leaves `[ ] text` / `[x] text` as literal text
  # inside `<li>`. Promote those to a clickable checkbox item that the
  # client serializes back to `- [ ] ` / `- [x] `.
  defp apply_task_lists(html) do
    html
    |> unwrap_loose_task_items()
    |> convert_task_checkboxes()
  end

  # A *loose* list (any blank line between items) wraps each item's content
  # in a `<p>`: `<li><p>text</p></li>`. The hybrid editor expects inline
  # content directly inside the `<li>` — a `<p>` inside traps the cursor
  # (the current block resolves to the inner `<p>`, so Enter inserts a
  # nested paragraph instead of a new list item and the bullet gets stuck).
  # Unwrap the single-paragraph case back to `<li>text</li>`. The negative
  # lookahead keeps the match to ONE paragraph so genuinely multi-block
  # items (`<li><p>a</p><p>b</p></li>`, `<li><p>a</p><ul>…</ul></li>`) are
  # left untouched. Runs before `apply_task_lists` so loose checklists are
  # unwrapped here and still get their checkbox.
  defp unwrap_loose_list_items(html) do
    Regex.replace(
      ~r/<li([^>]*)>\s*<p>((?:(?!<\/p>)[\s\S])*?)<\/p>\s*<\/li>/,
      html,
      "<li\\1>\\2</li>"
    )
  end

  # A *loose* list (any blank line between items) wraps each item's content
  # in a `<p>`: `<li><p>[ ] x</p></li>`. Unwrap task items back to
  # `<li>[ ] x</li>` so the checkbox match still fires — otherwise loose
  # checklists round-trip as literal "[ ] x" text.
  defp unwrap_loose_task_items(html) do
    Regex.replace(
      ~r/<li>\s*<p>\s*(\[[ xX]\][\s\S]*?)<\/p>\s*<\/li>/,
      html,
      "<li>\\1</li>"
    )
  end

  defp convert_task_checkboxes(html) do
    Regex.replace(~r/<li>\s*\[([ xX])\]\s?/, html, fn _full, mark ->
      checked = if mark in ["x", "X"], do: "true", else: "false"

      ~s(<li class="leaf-task" data-checked="#{checked}"><span class="leaf-task-box" contenteditable="false"></span>)
    end)
  end

  # Convert `||text||` (Discord-style spoiler) to <span class="leaf-spoiler">.
  # Skip anything inside <code>…</code> or <pre>…</pre> so literal pipes in
  # code samples stay literal.
  defp apply_spoiler_syntax(html) do
    html
    |> String.split(~r/(<(?:pre|code)\b[^>]*>.*?<\/(?:pre|code)>)/is, include_captures: true)
    |> Enum.map_join("", fn chunk ->
      if String.match?(chunk, ~r/^<(?:pre|code)\b/i) do
        chunk
      else
        String.replace(chunk, ~r/\|\|(.+?)\|\|/s, "<span class=\"leaf-spoiler\">\\1</span>")
      end
    end)
  end

  defp sanitize_html(html, deny) when is_binary(html) and is_list(deny) do
    html
    |> maybe_strip_html_links(deny)
    |> maybe_strip_html_images(deny)
  end

  defp sanitize_markdown(markdown, deny) when is_binary(markdown) and is_list(deny) do
    markdown
    |> maybe_strip_markdown_images(deny)
    |> maybe_strip_markdown_links(deny)
  end

  defp maybe_strip_html_links(html, deny) do
    if :links in deny do
      String.replace(html, ~r/<a\b[^>]*>(.*?)<\/a>/is, "\\1")
    else
      html
    end
  end

  defp maybe_strip_html_images(html, deny) do
    if :images in deny do
      String.replace(html, ~r/<img\b[^>]*\/?\s*>/is, "")
    else
      html
    end
  end

  defp maybe_strip_markdown_images(markdown, deny) do
    if :images in deny do
      String.replace(markdown, ~r/!\[(.*?)\]\((.*?)\)/, "")
    else
      markdown
    end
  end

  defp maybe_strip_markdown_links(markdown, deny) do
    if :links in deny do
      String.replace(markdown, ~r/(?<!!)\[(.*?)\]\((.*?)\)/, "\\1")
    else
      markdown
    end
  end

  # Wrap `#tag` occurrences in a decoration span so hashtags read as tags
  # rather than prose. Two things keep this safe:
  #
  # - `<span>` serializes back as its own text (see `convertNode`), so the
  #   markdown stays `#tag` and nothing about the round trip changes.
  # - Substitution only happens in text runs — never inside a tag, and
  #   never inside `<pre>` / `<code>` / `<a>`, where a `#` is a literal or
  #   a URL fragment rather than a tag.
  #
  # The leading-boundary group mirrors the `:word_start` suggestion
  # boundary, so `/page#section` is left alone for the same reason the
  # popup doesn't open there.
  @hashtag_re ~r/(^|[\s(\[>])#(\p{L}[\p{L}\p{N}_-]*)/u
  @hashtag_skip_re ~r{(<(?:pre|code|a)\b[^>]*>.*?</(?:pre|code|a)>)}is

  defp decorate_hashtags(html) do
    html
    |> String.split(@hashtag_skip_re, include_captures: true)
    |> Enum.map_join("", &decorate_hashtags_chunk/1)
  end

  defp decorate_hashtags_chunk(chunk) do
    if Regex.match?(~r/^<(?:pre|code|a)\b/i, chunk) do
      chunk
    else
      chunk
      |> String.split(~r/(<[^>]*>)/, include_captures: true)
      |> Enum.map_join("", &decorate_hashtags_text/1)
    end
  end

  defp decorate_hashtags_text("<" <> _ = tag), do: tag

  defp decorate_hashtags_text(text) do
    Regex.replace(@hashtag_re, text, ~s(\\1<span class="leaf-hashtag">#\\2</span>))
  end

  # Wrap `[[Target]]` in a decoration span so wiki links read as links rather
  # than literal brackets. Deliberately a `<span>`, never an `<a>`: `convertNode`
  # serializes an unknown span as its own text, so the markdown stays `[[Target]]`
  # and the round trip is unchanged — whereas an `<a>` would serialize as
  # `[label](href)` and rewrite the document into ordinary markdown links.
  #
  # Three shapes, matching Obsidian: `[[Target]]`, `[[Target|Alias]]` and
  # `[[Target#Heading]]`. The visible text is the alias where one is given, the
  # target otherwise; the target and heading ride along as data attributes so
  # the client can ask the host to resolve them.
  #
  # Skips `<pre>`, `<code>` and `<a>` for the same reason hashtags do: inside
  # them the brackets are literal, or already part of a link.
  @wiki_link_re ~r/\[\[([^\[\]|#]+?)(?:#([^\[\]|]+?))?(?:\|([^\[\]]+?))?\]\]/
  @wiki_link_skip_re ~r{(<(?:pre|code|a)\b[^>]*>.*?</(?:pre|code|a)>)}is

  defp decorate_wiki_links(html) do
    html
    |> String.split(@wiki_link_skip_re, include_captures: true)
    |> Enum.map_join("", &decorate_wiki_links_chunk/1)
  end

  defp decorate_wiki_links_chunk(chunk) do
    if Regex.match?(~r/^<(?:pre|code|a)\b/i, chunk) do
      chunk
    else
      chunk
      |> String.split(~r/(<[^>]*>)/, include_captures: true)
      |> Enum.map_join("", &decorate_wiki_links_text/1)
    end
  end

  defp decorate_wiki_links_text("<" <> _ = tag), do: tag

  defp decorate_wiki_links_text(text) do
    Regex.replace(@wiki_link_re, text, fn _whole, target, heading, alias_text ->
      wiki_link_span(String.trim(target), String.trim(heading), String.trim(alias_text))
    end)
  end

  defp wiki_link_span(target, heading, alias_text) do
    label = if alias_text == "", do: display_target(target, heading), else: alias_text

    # The raw source is carried verbatim so the client can rebuild the exact
    # `[[…]]` text without re-deriving it from the parts.
    raw = "[[" <> target <> heading_suffix(heading) <> alias_suffix(alias_text) <> "]]"

    ~s(<span class="leaf-wikilink" data-leaf-wikilink="#{escape_attr(target)}") <>
      heading_attr(heading) <>
      ~s( data-leaf-wikilink-raw="#{escape_attr(raw)}">) <>
      escape_text(label) <> "</span>"
  end

  defp display_target(target, ""), do: target
  defp display_target(target, heading), do: target <> " › " <> heading

  defp heading_suffix(""), do: ""
  defp heading_suffix(heading), do: "#" <> heading

  defp alias_suffix(""), do: ""
  defp alias_suffix(alias_text), do: "|" <> alias_text

  defp heading_attr(""), do: ""
  defp heading_attr(heading), do: ~s( data-leaf-wikilink-heading="#{escape_attr(heading)}")

  # Custom component tags that the host forgot to declare in
  # `preserve_tags` are the single most expensive mistake this library
  # allows: the visual surfaces flatten them into loose paragraphs and
  # autosave writes that back over the only copy. Nothing here can fix
  # that — only the declaration can — but a named warning turns silent
  # irreversible content loss into a one-line diagnosis.
  #
  # Warned once per tag name per editor process (the LiveView owning it),
  # so a re-render storm doesn't flood the log.
  @unpreserved_tag_re ~r/<([A-Z][A-Za-z0-9]*)\b/

  defp warn_unpreserved_tags(content, preserve_tags) when is_binary(content) do
    if Application.get_env(:leaf, :warn_unpreserved_tags, true) do
      declared = MapSet.new(preserve_tags, &String.downcase(to_string(&1)))
      already_warned = Process.get(:leaf_warned_tags, MapSet.new())

      undeclared =
        content
        # A tag inside a code fence or inline code is a code sample, not
        # content the editor will mangle.
        |> String.replace(~r/```.*?```/s, "")
        |> String.replace(~r/`[^`\n]*`/, "")
        |> then(&Regex.scan(@unpreserved_tag_re, &1, capture: :all_but_first))
        |> Enum.map(&hd/1)
        |> Enum.uniq()
        |> Enum.reject(&(String.downcase(&1) in declared or &1 in already_warned))

      if undeclared != [] do
        Process.put(:leaf_warned_tags, MapSet.union(already_warned, MapSet.new(undeclared)))
        Logger.warning(unpreserved_tags_message(undeclared))
      end
    end

    :ok
  end

  defp warn_unpreserved_tags(_content, _preserve_tags), do: :ok

  defp unpreserved_tags_message(tags) do
    named = Enum.map_join(tags, ", ", &"<#{&1}>")
    declaration = Enum.map_join(tags, ", ", &~s("#{&1}"))

    """
    [leaf] content contains custom tag(s) #{named} that are not declared in `preserve_tags`.

    The visual and hybrid surfaces flatten undeclared tags into loose paragraphs on the \
    first keystroke, and autosave then writes that back over the original — the tag and \
    everything it wrapped are gone. Declare them:

        <.leaf_editor … preserve_tags={[#{declaration}]} />

    Silence this warning with: config :leaf, warn_unpreserved_tags: false
    """
  end

  defp validate_deny!(deny) when is_list(deny) do
    if Enum.all?(@mode_order, &mode_denied?(&1, deny)) do
      raise ArgumentError, """
      Leaf: `deny` removes every editing mode, leaving nothing to render.

      Got: #{inspect(deny)}

      At least one of :visual_mode, :hybrid_mode, :markdown_mode, :html_mode \
      must stay allowed.
      """
    end

    :ok
  end

  defp validate_deny!(_deny), do: :ok

  # A denied mode falls back to the first allowed one in @mode_order rather
  # than to a hardcoded :visual — which stopped being a safe default the
  # moment :visual itself became deniable.
  defp normalize_mode(mode, deny)
       when mode in [:visual, :hybrid, :markdown, :html] and is_list(deny) do
    if mode_denied?(mode, deny) do
      validate_deny!(deny)
      Enum.find(@mode_order, &(not mode_denied?(&1, deny)))
    else
      mode
    end
  end

  defp mode_denied?(:hybrid, deny), do: :hybrid_mode in deny
  defp mode_denied?(:visual, deny), do: :visual_mode in deny
  defp mode_denied?(:markdown, deny), do: :markdown_mode in deny
  defp mode_denied?(:html, deny), do: :html_mode in deny
end
