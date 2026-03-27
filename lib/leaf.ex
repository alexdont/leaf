defmodule Leaf do
  @moduledoc """
  Dual-mode content editor LiveComponent with visual (WYSIWYG) and markdown modes.

  Visual mode uses a contenteditable div with vanilla JS (no npm dependencies).
  Markdown mode uses a plain textarea with toolbar support.
  Content syncs between modes using Earmark (markdown→HTML) and client-side
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
  - `{:leaf_insert_request, %{editor_id, type: :image | :video}}` — Insert requested
  - `{:leaf_mode_changed, %{editor_id, mode: :visual | :markdown}}` — Mode switched

  ## Commands from Parent

  Use `send_update/2`:

      send_update(Leaf, id: "my-editor", action: :insert_image, url: "https://...", alt: "description")
      send_update(Leaf, id: "my-editor", action: :set_content, content: "# Hello")
      send_update(Leaf, id: "my-editor", action: :set_mode, mode: :visual)

  ## JS Setup

  Add to your app.js:

      import "../../../deps/leaf/priv/static/assets/leaf.js"

      let Hooks = {
        Leaf: window.LeafHooks.Leaf,
        // ... your other hooks
      }

  ## Gettext (optional)

  To enable translations, configure a gettext backend:

      config :leaf, :gettext_backend, MyApp.Gettext

  Otherwise, English strings are used as-is.
  """

  use Phoenix.LiveComponent

  import Phoenix.HTML, only: [raw: 1]

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
  attr(:deny, :list, default: [])
  attr(:placeholder, :string, default: "Write something...")
  attr(:readonly, :boolean, default: false)
  attr(:height, :string, default: "480px")
  attr(:min_height, :string, default: nil)
  attr(:max_height, :string, default: nil)
  attr(:debounce, :integer, default: 400)
  attr(:flush_on_blur, :boolean, default: true)
  attr(:emit_events, :boolean, default: false)
  attr(:toolbar_extra, :list, default: [])
  attr(:toolbar_layout, :atom, default: :fixed, values: [:fixed, :floating, :both])
  attr(:preserve_tags, :list, default: [])
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

  attr(:gettext_backend, :any, default: nil)
  attr(:upload_handler, :any, default: nil)
  attr(:sync_input_name, :string, default: nil)
  attr(:class, :string, default: nil)
  attr(:script_nonce, :string, default: "")

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
     |> assign_new(:gettext_backend, fn -> nil end)
     |> assign_new(:readonly, fn -> false end)
     |> assign_new(:upload_handler, fn -> nil end)
     |> assign_new(:sync_input_name, fn -> nil end)
     |> assign_new(:loading_preset, fn -> :random end)
     |> assign_new(:loading_text, fn -> nil end)
     |> assign_new(:script_nonce, fn -> "" end)}
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

  def update(%{action: :set_content, content: content}, socket) do
    deny = Map.get(socket.assigns, :deny, [])
    sanitized_markdown = sanitize_markdown(content, deny)

    html =
      sanitized_markdown
      |> markdown_to_html(preserve_tags(socket))
      |> sanitize_html(deny)

    {:ok,
     socket
     |> assign(:content, sanitized_markdown)
     |> assign(:visual_html, html)
     |> push_event("leaf-command:#{socket.assigns.id}", %{
       action: "set_content",
       content: sanitized_markdown,
       html: html
     })}
  end

  def update(%{action: :set_mode, mode: mode}, socket)
      when mode in [:visual, :hybrid, :markdown, :html] do
    deny = Map.get(socket.assigns, :deny, [])
    mode = normalize_mode(mode, deny)

    {:ok,
     socket
     |> assign(:mode, mode)
     |> push_event("leaf-command:#{socket.assigns.id}", %{
       action: "set_mode",
       mode: to_string(mode)
     })}
  end

  def update(%{action: :insert_markdown} = assigns, socket) do
    text = Map.get(assigns, :text, "")

    {:ok,
     push_event(socket, "leaf-command:#{socket.assigns.id}", %{
       action: "insert_markdown",
       text: text
     })}
  end

  def update(%{action: :flush}, socket) do
    {:ok, push_event(socket, "leaf-command:#{socket.assigns.id}", %{action: "flush"})}
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
    mode = normalize_mode(socket.assigns.mode, deny)

    socket = assign(socket, :mode, mode)

    socket =
      assign_new(socket, :visual_html, fn ->
        socket.assigns.content
        |> sanitize_markdown(deny)
        |> markdown_to_html(preserve_tags(socket))
        |> sanitize_html(deny)
      end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    Process.put(:leaf_gettext_backend, assigns[:gettext_backend])

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
      data-deny-links={to_string(:links in @deny)}
      data-deny-images={to_string(:images in @deny)}
      data-deny-video={to_string(:video in @deny)}
      data-deny-markdown-mode={to_string(:markdown_mode in @deny)}
      data-deny-html-mode={to_string(:html_mode in @deny)}
    >
      {loading_state_style_tag(@height, @script_nonce)}

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
                  class="hidden absolute top-full left-0 menu bg-base-200 rounded-box z-50 w-28 p-1 shadow-sm"
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
                    <span class="text-base font-bold leading-none">...</span>
                  </button>
                  <ul
                    class="hidden absolute top-full left-0 menu bg-base-200 rounded-box z-50 w-44 p-1 shadow-sm"
                    data-inline-more-menu
                  >
                    <li>
                      <button
                        type="button"
                        data-toolbar-action="superscript"
                      >
                        <span class="text-xs">X<sup class="text-[0.5rem]">2</sup></span>
                        <span>{t("Superscript")}</span>
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        data-toolbar-action="subscript"
                      >
                        <span class="text-xs">X<sub class="text-[0.5rem]">2</sub></span>
                        <span>{t("Subscript")}</span>
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        data-toolbar-action="code"
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
                        <span>{t("Inline Code")}</span>
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        data-toolbar-action="spoiler"
                      >
                        <span class="inline-block w-3.5 h-2.5 bg-current rounded-sm" aria-hidden="true"></span>
                        <span>{t("Spoiler")}</span>
                      </button>
                    </li>
                    <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="lists-title">
                      {t("Lists")}
                    </li>
                    <li class="hidden" data-compact-overflow="list-bullet">
                      <button type="button" data-toolbar-action="bulletList">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                          <path fill-rule="evenodd" d="M6 4.75A.75.75 0 016.75 4h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 4.75zM6 10a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 10zm0 5.25a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75a.75.75 0 01-.75-.75zM1.99 4.75a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 15.25a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 10a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1V10z" clip-rule="evenodd" />
                        </svg>
                        <span>{t("Bullet List")}</span>
                      </button>
                    </li>
                    <li class="hidden" data-compact-overflow="list-ordered">
                      <button type="button" data-toolbar-action="orderedList">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                          <path d="M3.0002 1.25C2.58599 1.25 2.2502 1.58579 2.2502 2C2.2502 2.41421 2.58599 2.75 3.0002 2.75H3.2502V5.25C3.2502 5.66421 3.58599 6 4.0002 6C4.41441 6 4.7502 5.66421 4.7502 5.25V2C4.7502 1.58579 4.41441 1.25 4.0002 1.25H3.0002Z" />
                          <path d="M2.97049 8.65372C3.29513 8.55397 3.64067 8.5 4.0002 8.5C4.16835 8.5 4.33333 8.5118 4.49444 8.53453C4.49127 8.53922 4.48691 8.54312 4.48165 8.54575L2.41479 9.57918C2.1607 9.70622 2.0002 9.96592 2.0002 10.25V11.25C2.0002 11.6642 2.33599 12 2.7502 12H5.2502C5.66441 12 6.0002 11.6642 6.0002 11.25C6.0002 10.8358 5.66441 10.5 5.2502 10.5H3.92725L5.15247 9.88739C5.67202 9.62762 6.0002 9.09661 6.0002 8.51574C6.0002 7.86944 5.57097 7.18897 4.80714 7.06489C4.54401 7.02215 4.27442 7 4.0002 7C3.48967 7 2.99569 7.07676 2.52991 7.21988C2.13397 7.34154 1.91162 7.76115 2.03328 8.15709C2.15494 8.55303 2.57455 8.77538 2.97049 8.65372Z" />
                          <path d="M7.75 3C7.33579 3 7 3.33579 7 3.75C7 4.16421 7.33579 4.5 7.75 4.5H17.25C17.6642 4.5 18 4.16421 18 3.75C18 3.33579 17.6642 3 17.25 3H7.75Z" />
                          <path d="M7.75 9.25C7.33579 9.25 7 9.58579 7 10C7 10.4142 7.33579 10.75 7.75 10.75H17.25C17.6642 10.75 18 10.4142 18 10C18 9.58579 17.6642 9.25 17.25 9.25H7.75Z" />
                          <path d="M7.75 15.5C7.33579 15.5 7 15.8358 7 16.25C7 16.6642 7.33579 17 7.75 17H17.25C17.6642 17 18 16.6642 18 16.25C18 15.8358 17.6642 15.5 17.25 15.5H7.75Z" />
                          <path d="M2.625 13.875C2.21079 13.875 1.875 14.2108 1.875 14.625C1.875 15.0392 2.21079 15.375 2.625 15.375H4.125C4.19404 15.375 4.25 15.431 4.25 15.5C4.25 15.569 4.19404 15.625 4.125 15.625H3.5C3.08579 15.625 2.75 15.9608 2.75 16.375C2.75 16.7892 3.08579 17.125 3.5 17.125H4.125C4.19404 17.125 4.25 17.181 4.25 17.25C4.25 17.319 4.19404 17.375 4.125 17.375H2.625C2.21079 17.375 1.875 17.7108 1.875 18.125C1.875 18.5392 2.21079 18.875 2.625 18.875H4.125C5.02246 18.875 5.75 18.1475 5.75 17.25C5.75 16.9278 5.65625 16.6276 5.49454 16.375C5.65625 16.1224 5.75 15.8222 5.75 15.5C5.75 14.6025 5.02246 13.875 4.125 13.875H2.625Z" />
                        </svg>
                        <span>{t("Numbered List")}</span>
                      </button>
                    </li>
                    <%= if @preset == :advanced do %>
                      <li class="hidden" data-compact-overflow="list-indent">
                        <button type="button" data-toolbar-action="indent">
                          <span>{t("Increase Indent")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="list-outdent">
                        <button type="button" data-toolbar-action="outdent">
                          <span>{t("Decrease Indent")}</span>
                        </button>
                      </li>
                    <% end %>
                    <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="insert-title">
                      {t("Insert")}
                    </li>
                    <li class="hidden" data-compact-overflow="insert-link">
                      <button type="button" data-toolbar-action="link">
                        <span>{t("Link")}</span>
                      </button>
                    </li>
                    <li class="hidden" data-compact-overflow="insert-emoji">
                      <button type="button" data-toolbar-action="emoji">
                        <span>{t("Emoji")}</span>
                      </button>
                    </li>
                    <%= if @preset == :advanced and :image in @toolbar do %>
                      <li class="hidden" data-compact-overflow="insert-image">
                        <button type="button" data-toolbar-action="insert-image">
                          <span>{t("Image")}</span>
                        </button>
                      </li>
                    <% end %>
                    <%= if @preset == :advanced and :video in @toolbar do %>
                      <li class="hidden" data-compact-overflow="insert-video">
                        <button type="button" data-toolbar-action="insert-video">
                          <span>{t("Video")}</span>
                        </button>
                      </li>
                    <% end %>
                    <%= if @preset == :advanced do %>
                      <li class="hidden" data-compact-overflow="insert-table">
                        <button type="button" data-toolbar-action="table">
                          <span>{t("Table")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-blockquote">
                        <button type="button" data-toolbar-action="blockquote">
                          <span>{t("Blockquote")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-codeblock">
                        <button type="button" data-toolbar-action="codeBlock">
                          <span>{t("Code Block")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-hr">
                        <button type="button" data-toolbar-action="horizontalRule">
                          <span>{t("Horizontal Rule")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="taskList">
                          <span>{t("Task List")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="callout">
                          <span>{t("Callout")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="detailsBlock">
                          <span>{t("Details / Accordion")}</span>
                        </button>
                      </li>
                      <li class="hidden" data-compact-overflow="insert-more-extra">
                        <button type="button" data-toolbar-action="symbols">
                          <span>{t("Symbols / Date")}</span>
                        </button>
                      </li>
                    <% end %>
                    <li class="hidden" data-compact-overflow="remove-format">
                      <button type="button" data-toolbar-action="removeFormat">
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          viewBox="0 0 20 20"
                          fill="currentColor"
                          class="w-3.5 h-3.5"
                        >
                          <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                        </svg>
                        <span>{t("Remove Formatting")}</span>
                      </button>
                    </li>
                    <%= if @toolbar_extra != [] and not @readonly do %>
                      <li class="menu-title text-xs px-2 pt-1 hidden" data-compact-overflow="extra">
                        {t("Components")}
                      </li>
                      <%= for btn <- @toolbar_extra do %>
                        <li class="hidden" data-compact-overflow="extra">
                          <button type="button" data-host-action={efetch(btn, :id)}>
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
                        <button type="button" data-toolbar-action="copyMarkdown"><span>{t("Copy as Markdown")}</span></button>
                      </li>
                      <li class="hidden" data-compact-overflow="export">
                        <button type="button" data-toolbar-action="copyHtml"><span>{t("Copy as HTML")}</span></button>
                      </li>
                      <li class="hidden" data-compact-overflow="export">
                        <button type="button" data-toolbar-action="downloadMarkdown"><span>{t("Download .md")}</span></button>
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
                    class="hidden absolute top-full left-0 menu bg-base-200 rounded-box z-[10000] w-40 p-1 shadow-sm"
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
                  class="hidden absolute top-full left-0 menu bg-base-200 rounded-box z-50 w-44 p-1 shadow-sm"
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
                  <span class="text-base font-bold leading-none">...</span>
                </button>
                <ul
                  class="hidden absolute top-full left-0 menu bg-base-200 rounded-box z-50 w-40 p-1 shadow-sm"
                  data-insert-more-menu
                >
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="blockquote"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                        class="w-3.5 h-3.5"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M2 3.75A.75.75 0 012.75 3h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 3.75zm3 4A.75.75 0 015.75 7h8.5a.75.75 0 010 1.5h-8.5A.75.75 0 015 7.75zm0 4A.75.75 0 015.75 11h8.5a.75.75 0 010 1.5h-8.5a.75.75 0 01-.75-.75zm-3 4A.75.75 0 012.75 15h14.5a.75.75 0 010 1.5H2.75a.75.75 0 01-.75-.75z"
                          clip-rule="evenodd"
                        />
                      </svg>
                      <span>{t("Blockquote")}</span>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="codeBlock"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                        class="w-3.5 h-3.5"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M6.28 5.22a.75.75 0 010 1.06L2.56 10l3.72 3.72a.75.75 0 01-1.06 1.06L.97 10.53a.75.75 0 010-1.06l4.25-4.25a.75.75 0 011.06 0zm7.44 0a.75.75 0 011.06 0l4.25 4.25a.75.75 0 010 1.06l-4.25 4.25a.75.75 0 01-1.06-1.06L17.44 10l-3.72-3.72a.75.75 0 010-1.06zM11.377 2.011a.75.75 0 01.612.867l-2.5 14.5a.75.75 0 01-1.478-.255l2.5-14.5a.75.75 0 01.866-.612z"
                          clip-rule="evenodd"
                        />
                      </svg>
                      <span>{t("Code Block")}</span>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="horizontalRule"
                    >
                      <span class="text-lg font-bold">&mdash;</span>
                      <span>{t("Horizontal Rule")}</span>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="detailsBlock"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path fill-rule="evenodd" d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                      </svg>
                      <span>{t("Details / Accordion")}</span>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="taskList"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path fill-rule="evenodd" d="M7.53 4.97a.75.75 0 0 1 0 1.06L5.06 8.5 7.53 10.97a.75.75 0 0 1-1.06 1.06l-3-3a.75.75 0 0 1 0-1.06l3-3a.75.75 0 0 1 1.06 0ZM10.75 7.5a.75.75 0 0 0 0 1.5h6.5a.75.75 0 0 0 0-1.5h-6.5Z" clip-rule="evenodd" />
                      </svg>
                      <span>{t("Task List")}</span>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="callout"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                        <path fill-rule="evenodd" d="M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-7-4a1 1 0 1 1-2 0 1 1 0 0 1 2 0ZM9 9a.75.75 0 0 0 0 1.5h.253a.25.25 0 0 1 .244.304l-.459 2.066A1.75 1.75 0 0 0 10.747 15H11a.75.75 0 0 0 0-1.5h-.253a.25.25 0 0 1-.244-.304l.459-2.066A1.75 1.75 0 0 0 9.253 9H9Z" clip-rule="evenodd" />
                      </svg>
                      <span>{t("Callout")}</span>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      data-toolbar-action="symbols"
                    >
                      <span class="text-sm font-semibold w-3.5 text-center">Ω</span>
                      <span>{t("Symbols / Date")}</span>
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
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="w-3.5 h-3.5"
                >
                  <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                </svg>
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
        <%= if @toolbar_extra != [] and not @readonly do %>
          <div class="divider divider-horizontal mx-0.5 h-6" data-toolbar-divider="extra"></div>
          <div class="flex items-center gap-0.5" data-toolbar-extra data-toolbar-overflow="extra">
            <%= for btn <- @toolbar_extra do %>
              <button
                type="button"
                data-host-action={efetch(btn, :id)}
                class={["btn btn-xs btn-ghost px-2", efetch(btn, :class)]}
                title={efetch(btn, :title)}
                aria-label={efetch(btn, :title)}
              >
                <%= if icon = efetch(btn, :icon) do %>{raw(icon)}<% end %>
                <%= if label = efetch(btn, :label) do %><span>{label}</span><% end %>
              </button>
            <% end %>
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

        <%!-- Mode Switcher --%>
        <div class="flex items-center gap-0.5" data-mode-switcher="inline">
          <div class="divider divider-horizontal mx-0.5 h-6"></div>
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
          <%= unless :markdown_mode in @deny do %>
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
          <%= unless :html_mode in @deny do %>
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
            class="absolute top-full right-0 menu bg-base-200 rounded-box z-50 w-36 p-1 shadow-sm"
            data-mode-menu
          >
            <li class="menu-title text-xs px-2 pt-1">{t("Mode")}</li>
            <li>
              <button
                type="button"
                data-mode-tab="hybrid"
                class={(@mode == :hybrid && "btn-active") || "btn-ghost"}
              >
                <span>{t("Hybrid")}</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                data-mode-tab="visual"
                class={(@mode == :visual && "btn-active") || "btn-ghost"}
              >
                <span>{t("Visual")}</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                data-mode-tab="markdown"
                class={(@mode == :markdown && "btn-active") || "btn-ghost"}
              >
                <span>{t("Markdown")}</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                data-mode-tab="html"
                class={(@mode == :html && "btn-active") || "btn-ghost"}
              >
                <span>{t("HTML")}</span>
              </button>
            </li>
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
              <span class="text-base font-bold leading-none">...</span>
            </summary>
            <ul class="absolute top-full left-0 menu bg-base-200 rounded-box z-50 w-44 p-1 shadow-sm">
              <li class="menu-title text-xs px-2 pt-1">{t("Format")}</li>
              <li><button type="button" data-toolbar-action="heading2"><span>{t("Heading")}</span></button></li>
              <li><button type="button" data-toolbar-action="orderedList"><span>{t("Numbered List")}</span></button></li>
              <li><button type="button" data-toolbar-action="code"><span>{t("Inline Code")}</span></button></li>
              <%= if @preset == :advanced do %>
                <li><button type="button" data-toolbar-action="blockquote"><span>{t("Blockquote")}</span></button></li>
                <li><button type="button" data-toolbar-action="codeBlock"><span>{t("Code Block")}</span></button></li>
                <li class="menu-title text-xs px-2 pt-1">{t("Insert")}</li>
                <li><button type="button" data-toolbar-action="horizontalRule"><span>{t("Horizontal Rule")}</span></button></li>
                <li><button type="button" data-toolbar-action="taskList"><span>{t("Task List")}</span></button></li>
                <li><button type="button" data-toolbar-action="callout"><span>{t("Callout")}</span></button></li>
                <li><button type="button" data-toolbar-action="detailsBlock"><span>{t("Details / Accordion")}</span></button></li>
                <li><button type="button" data-toolbar-action="symbols"><span>{t("Symbols / Date")}</span></button></li>
                <%= if :image in @toolbar do %>
                  <li><button type="button" data-toolbar-action="insert-image"><span>{t("Image")}</span></button></li>
                <% end %>
                <%= if :video in @toolbar do %>
                  <li><button type="button" data-toolbar-action="insert-video"><span>{t("Video")}</span></button></li>
                <% end %>
              <% end %>
              <%= if @toolbar_extra != [] and not @readonly do %>
                <li class="menu-title text-xs px-2 pt-1">{t("Components")}</li>
                <%= for btn <- @toolbar_extra do %>
                  <li>
                    <button type="button" data-host-action={efetch(btn, :id)}>
                      <span>{efetch(btn, :label) || efetch(btn, :title) || efetch(btn, :id)}</span>
                    </button>
                  </li>
                <% end %>
              <% end %>
              <%= if @export and not @readonly do %>
                <li class="menu-title text-xs px-2 pt-1">{t("Export")}</li>
                <li><button type="button" data-toolbar-action="copyMarkdown"><span>{t("Copy as Markdown")}</span></button></li>
                <li><button type="button" data-toolbar-action="copyHtml"><span>{t("Copy as HTML")}</span></button></li>
                <li><button type="button" data-toolbar-action="downloadMarkdown"><span>{t("Download .md")}</span></button></li>
              <% end %>
              <li class="menu-title text-xs px-2 pt-1">{t("Clean up")}</li>
              <li><button type="button" data-toolbar-action="removeFormat"><span>{t("Remove Formatting")}</span></button></li>
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
            <ul class="absolute top-full right-0 menu bg-base-200 rounded-box z-50 w-36 p-1 shadow-sm">
              <li class="menu-title text-xs px-2 pt-1">{t("Mode")}</li>
              <li><button type="button" data-mode-tab="hybrid" class={(@mode == :hybrid && "btn-active") || "btn-ghost"}><span>{t("Hybrid")}</span></button></li>
              <li><button type="button" data-mode-tab="visual" class={(@mode == :visual && "btn-active") || "btn-ghost"}><span>{t("Visual")}</span></button></li>
              <li><button type="button" data-mode-tab="markdown" class={(@mode == :markdown && "btn-active") || "btn-ghost"}><span>{t("Markdown")}</span></button></li>
              <li><button type="button" data-mode-tab="html" class={(@mode == :html && "btn-active") || "btn-ghost"}><span>{t("HTML")}</span></button></li>
              <%= if @preset == :advanced do %>
                <li class="menu-title text-xs px-2 pt-1">{t("View")}</li>
                <li><button type="button" data-toolbar-action="fullscreen"><span>{t("Fullscreen")}</span></button></li>
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

  def handle_event("markdown_content_changed", %{"content" => content} = params, socket) do
    sanitized_markdown = sanitize_markdown(content, socket.assigns.deny)
    html = sanitized_markdown |> markdown_to_html(preserve_tags(socket)) |> sanitize_html(socket.assigns.deny)

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
      |> markdown_to_html(preserve_tags(socket))
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
  defp t(string) do
    backend =
      Process.get(:leaf_gettext_backend) ||
        Application.get_env(:leaf, :gettext_backend)

    case backend do
      nil -> string
      backend -> Gettext.gettext(backend, string)
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
       they never spill onto a second row. */
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
  # (e.g. <Hero/>, <CTA/>) are pulled out of the markdown BEFORE Earmark
  # (which would otherwise mangle their form), rendered as atomic,
  # non-editable placeholder blocks, and restored verbatim. The client
  # serializes those placeholders straight back to their original source,
  # so custom XML round-trips byte-for-byte through visual/hybrid mode.
  defp markdown_to_html(nil, _), do: markdown_to_html(nil)
  defp markdown_to_html("", _), do: markdown_to_html("")

  defp markdown_to_html(markdown, preserve_tags)
       when is_list(preserve_tags) and preserve_tags != [] do
    {protected, store} = extract_preserved_tags(markdown, preserve_tags)

    protected
    |> markdown_to_html()
    |> restore_preserved_tags(store)
  end

  defp markdown_to_html(markdown, _), do: markdown_to_html(markdown)

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
  # source in a `data-leaf-raw` attribute. A standalone token that Earmark
  # wrapped in its own `<p>` stays a block; an inline token stays inline.
  defp restore_preserved_tags(html, store) do
    Enum.reduce(store, html, fn {token, raw}, acc ->
      escaped = raw |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      label = preserve_label(raw)

      wrapper =
        ~s(<span class="leaf-atomic" contenteditable="false" data-leaf-raw="#{escaped}"><span class="leaf-atomic-label">#{label}</span></span>)

      acc
      |> String.replace("<p>#{token}</p>", "<p>#{wrapper}</p>")
      |> String.replace(token, wrapper)
    end)
  end

  defp preserve_label(raw) do
    case Regex.run(~r/<\s*([A-Za-z][\w-]*)/, raw) do
      [_, name] -> name
      _ -> "block"
    end
  end

  defp markdown_to_html(nil), do: "<p><br></p>"
  defp markdown_to_html(""), do: "<p><br></p>"

  defp markdown_to_html(markdown) do
    case Earmark.as_html(markdown, breaks: true) do
      {:ok, html, _} -> clean_html(html)
      {:error, _, _} -> "<p>#{Phoenix.HTML.html_escape(markdown)}</p>"
    end
  end

  # Earmark outputs newlines after opening tags (e.g. "<h1>\nText</h1>\n").
  # Collapse those so HTML mode shows clean single-line tags.
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

  # GFM callouts: `> [!NOTE]` etc. Earmark leaves `[!NOTE]` as literal text
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

  # GFM task lists: Earmark leaves `[ ] text` / `[x] text` as literal text
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
      String.replace(markdown, ~r/\[(.*?)\]\((.*?)\)/, "\\1")
    else
      markdown
    end
  end

  defp normalize_mode(mode, deny) when mode in [:visual, :markdown, :html] and is_list(deny) do
    if mode_denied?(mode, deny), do: :visual, else: mode
  end

  defp mode_denied?(:markdown, deny), do: :markdown_mode in deny
  defp mode_denied?(:html, deny), do: :html_mode in deny
  defp mode_denied?(:visual, _deny), do: false
end
