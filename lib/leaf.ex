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
  attr(:placeholder, :string, default: "Write something...")
  attr(:readonly, :boolean, default: false)
  attr(:height, :string, default: "480px")
  attr(:debounce, :integer, default: 400)
  attr(:upload_handler, :any, default: nil)
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
     |> assign_new(:placeholder, fn -> "Write something..." end)
     |> assign_new(:height, fn -> "480px" end)
     |> assign_new(:debounce, fn -> 400 end)
     |> assign_new(:readonly, fn -> false end)
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
    html = markdown_to_html(content)

    {:ok,
     socket
     |> assign(:content, content)
     |> push_event("leaf-set-html:#{socket.assigns.id}", %{html: html})}
  end

  def update(%{action: :set_mode, mode: mode}, socket)
      when mode in [:visual, :hybrid, :markdown, :html] do
    {:ok,
     socket
     |> assign(:mode, mode)
     |> push_event("leaf-command:#{socket.assigns.id}", %{
       action: "set_mode",
       mode: to_string(mode)
     })}
  end

  def update(assigns, socket) do
    {parent_mode, assigns} = Map.pop(assigns, :mode, :hybrid)

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn -> parent_mode end)

    socket =
      assign_new(socket, :visual_html, fn ->
        markdown_to_html(socket.assigns.content)
      end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Leaf"
      class="min-w-0"
      data-leaf-mount-state="loading"
      data-editor-id={@id}
      data-mode={to_string(@mode)}
      data-placeholder={@placeholder}
      data-debounce={@debounce}
      data-readonly={@readonly}
      data-height={@height}
      data-has-upload={to_string(@upload_handler != nil)}
    >
      {loading_state_style_tag(@height, @script_nonce)}

      <%!-- Toolbar --%>
      <div
        id={"#{@id}-toolbar"}
        phx-update="ignore"
        class="flex flex-wrap items-center gap-1 mb-2 p-2 bg-base-200 rounded-lg min-w-0"
        data-visual-toolbar
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
                    <span class="text-base font-bold leading-none">&#8942;</span>
                  </button>
                  <ul
                    class="hidden absolute top-full left-0 menu bg-base-200 rounded-box z-50 w-36 p-1 shadow-sm"
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

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Lists --%>
            <div class="flex items-center gap-0.5 mr-2">
              <button
                type="button"
                data-toolbar-action="bulletList"
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

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Insert --%>
            <div class="flex items-center gap-0.5 mr-2">
              <button
                type="button"
                data-toolbar-action="link"
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
              <button
                type="button"
                data-toolbar-action="emoji"
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
              <%= if @preset == :advanced and :image in @toolbar do %>
                <div class="relative inline-flex" data-image-split-btn>
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
              <%= if @preset == :advanced and :video in @toolbar do %>
                <button
                  type="button"
                  data-toolbar-action="insert-video"
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
              <div class="relative" data-table-dropdown>
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
                </ul>
              </div>
              <%!-- More inserts --%>
              <div class="relative" data-insert-more-dropdown>
                <button
                  type="button"
                  class="btn btn-xs btn-ghost px-1.5"
                  title={t("More inserts")}
                  data-insert-more-trigger
                >
                  <span class="text-base font-bold leading-none">&#8942;</span>
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
                </ul>
              </div>
              <% end %>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Clear Formatting --%>
            <div class="flex items-center gap-0.5">
              <button
                type="button"
                data-toolbar-action="removeFormat"
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

        <%!-- Spacer --%>
        <div class="flex-1"></div>

        <%!-- Mode Switcher --%>
        <div class="flex items-center gap-0.5" data-mode-switcher>
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
          <button
            type="button"
            data-mode-tab="html"
            class={["btn btn-xs px-2", (@mode == :html && "btn-active") || "btn-ghost"]}
            title={t("HTML mode")}
          >
            &lt;/&gt;
          </button>
        </div>
      </div>

      <div class="border border-base-300 overflow-hidden" style="border-radius: 0.5rem">
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
            class={[
              "content-editor-visual",
              "overflow-auto p-4 pl-10",
              "focus:outline-none",
              @readonly && "opacity-70 cursor-not-allowed"
            ]}
            style={"min-height: #{@height}; height: #{@height}; resize: vertical;"}
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
            style={"min-height: #{@height}; resize: vertical;"}
            placeholder={@placeholder}
            readonly={@readonly}
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
            style={"min-height: #{@height}; resize: vertical;"}
            placeholder="<p>Write HTML here...</p>"
            readonly={@readonly}
            phx-debounce={@debounce}
          ><%= @visual_html %></textarea>
        </div>
        </div>

        <div id={"#{@id}-footer"} phx-update="ignore" data-editor-footer class="flex justify-end gap-4 px-3 py-1 text-xs text-base-content/50 border-t border-base-300">
          <span data-word-count>0 words</span>
          <span data-char-count>0 chars</span>
        </div>
      </div>
    </div>
    """
  end

  # -- Events from JS Hook --

  @impl true
  def handle_event("content_changed", %{"markdown" => markdown, "html" => html}, socket) do
    send(
      self(),
      {:leaf_changed,
       %{
         editor_id: socket.assigns.id,
         markdown: markdown,
         html: html
       }}
    )

    {:noreply, socket |> assign(:content, markdown) |> assign(:visual_html, html)}
  end

  def handle_event("markdown_content_changed", %{"content" => content}, socket) do
    html = markdown_to_html(content)

    send(
      self(),
      {:leaf_changed,
       %{
         editor_id: socket.assigns.id,
         markdown: content,
         html: html
       }}
    )

    {:noreply, assign(socket, :content, content)}
  end

  def handle_event("mode_changed", %{"mode" => mode} = params, socket) do
    mode_atom = String.to_existing_atom(mode)
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

  def handle_event("html_content_changed", %{"content" => html}, socket) do
    send(
      self(),
      {:leaf_changed,
       %{
         editor_id: socket.assigns.id,
         markdown: socket.assigns.content,
         html: html
       }}
    )

    {:noreply, socket}
  end

  def handle_event("sync_markdown_to_visual", %{"markdown" => markdown}, socket) do
    html = markdown_to_html(markdown)

    {:noreply, push_event(socket, "leaf-set-html:#{socket.assigns.id}", %{html: html})}
  end

  def handle_event("sync_html_to_visual", %{"html" => html}, socket) do
    {:noreply, push_event(socket, "leaf-set-html:#{socket.assigns.id}", %{html: html})}
  end

  def handle_event("convert_markdown_to_html", %{"markdown" => markdown}, socket) do
    html = markdown_to_html(markdown)

    {:noreply, push_event(socket, "leaf-set-html-textarea:#{socket.assigns.id}", %{html: html})}
  end

  # The image-URL dialog (and other media popovers) push these to signal the
  # server that a modal UI is active. Currently no-op on the server side —
  # they exist so a future hook can react (suspend autosave, freeze the
  # component, etc.) without the LiveView crashing on an unmatched event.
  def handle_event("media_ui_opened", _params, socket), do: {:noreply, socket}
  def handle_event("media_ui_closed", _params, socket), do: {:noreply, socket}

  # -- Helpers --

  defp t(string) do
    case Application.get_env(:leaf, :gettext_backend) do
      nil ->
        string

      backend ->
        Gettext.gettext(backend, string)
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

    /* Toolbar alignment — emitted inline so the icon row sits on a single
       centerline at first paint, before the JS hook injects the full
       editor stylesheet. Without this the toolbar is briefly jagged. */
    [data-visual-toolbar] svg { display: block; }
    [data-visual-toolbar] button { line-height: 1; }
    [data-visual-toolbar] [data-heading-dropdown],
    [data-visual-toolbar] [data-inline-more-dropdown],
    [data-visual-toolbar] [data-table-dropdown],
    [data-visual-toolbar] [data-insert-more-dropdown] {
      display: inline-flex;
      align-items: center;
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
       handler can reliably swap them to an editable `<p>---</p>`.
       Default HR is a 2-3px line that's nearly impossible to land on. */
    .content-editor-visual hr {
      padding: 6px 0;
      margin: 0.25em 0;
      cursor: pointer;
    }

    """
  end

  defp markdown_to_html(nil), do: ""
  defp markdown_to_html(""), do: ""

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
    |> apply_spoiler_syntax()
    |> String.trim()
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
end
