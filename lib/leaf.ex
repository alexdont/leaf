defmodule Leaf do
  @moduledoc """
  Dual-mode content editor LiveComponent with visual (WYSIWYG) and markdown modes.

  Visual mode uses a contenteditable div with vanilla JS (no npm dependencies).
  Markdown mode uses a plain textarea with toolbar support.
  Content syncs between modes using Earmark (markdown→HTML) and client-side
  HTML→markdown conversion.

  ## Usage

      <.live_component
        module={Leaf}
        id="my-editor"
        content={@content}
        mode={:visual}
        toolbar={[:image, :video]}
        placeholder="Write something..."
        readonly={false}
        height="480px"
        debounce={400}
      />

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
  import Leaf.Icon, only: [icon: 1]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:content, fn -> "" end)
     |> assign_new(:mode, fn -> :visual end)
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

  def update(%{action: :set_mode, mode: mode}, socket) when mode in [:visual, :markdown, :html] do
    {:ok,
     socket
     |> assign(:mode, mode)
     |> push_event("leaf-command:#{socket.assigns.id}", %{
       action: "set_mode",
       mode: to_string(mode)
     })}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

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
      data-editor-id={@id}
      data-mode={to_string(@mode)}
      data-placeholder={@placeholder}
      data-debounce={@debounce}
      data-readonly={@readonly}
      data-height={@height}
    >
      <%!-- Toolbar --%>
      <div
        id={"#{@id}-toolbar"}
        phx-update="ignore"
        class="flex flex-wrap items-center gap-1 mb-2 p-2 bg-base-200 rounded-lg"
        data-visual-toolbar
      >
        <%= unless @readonly do %>
          <div data-visual-toolbar-buttons class="contents">
            <%!-- Headings --%>
            <div class="flex items-center gap-0.5 mr-2">
              <button
                type="button"
                data-toolbar-action="heading1"
                class="btn btn-xs btn-ghost font-bold px-1.5"
                title={t("Heading 1")}
              >
                H1
              </button>
              <button
                type="button"
                data-toolbar-action="heading2"
                class="btn btn-xs btn-ghost font-bold px-1.5"
                title={t("Heading 2")}
              >
                H2
              </button>
              <button
                type="button"
                data-toolbar-action="heading3"
                class="btn btn-xs btn-ghost font-bold px-1.5"
                title={t("Heading 3")}
              >
                H3
              </button>
              <button
                type="button"
                data-toolbar-action="heading4"
                class="btn btn-xs btn-ghost font-bold px-1.5"
                title={t("Heading 4")}
              >
                H4
              </button>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Inline Formatting --%>
            <div class="flex items-center gap-0.5 mr-2">
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
              <button
                type="button"
                data-toolbar-action="superscript"
                class="btn btn-xs btn-ghost px-1.5"
                title={t("Superscript")}
              >
                <span class="text-xs">X<sup class="text-[0.5rem]">2</sup></span>
              </button>
              <button
                type="button"
                data-toolbar-action="subscript"
                class="btn btn-xs btn-ghost px-1.5"
                title={t("Subscript")}
              >
                <span class="text-xs">X<sub class="text-[0.5rem]">2</sub></span>
              </button>
              <button
                type="button"
                data-toolbar-action="code"
                class="btn btn-xs btn-ghost font-mono px-2"
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
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Links & Media --%>
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
              <%= if :image in @toolbar do %>
                <button
                  type="button"
                  data-toolbar-action="insert-image"
                  class="btn btn-xs btn-ghost px-2"
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
              <% end %>
              <%= if :video in @toolbar do %>
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
            </div>

            <%!-- Emoji --%>
            <div class="flex items-center gap-0.5 mr-2">
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
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Lists & Blocks --%>
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
                  <path d="M3 4.5a.5.5 0 01.5-.5h1a.5.5 0 01.5.5v2a.5.5 0 01-.5.5h-1a.5.5 0 01-.5-.5v-2zM7 5h10a1 1 0 110 2H7a1 1 0 110-2zM3 9.5a.5.5 0 01.5-.5h1a.5.5 0 01.5.5v2a.5.5 0 01-.5.5h-1a.5.5 0 01-.5-.5v-2zM7 10h10a1 1 0 110 2H7a1 1 0 110-2zM3 14.5a.5.5 0 01.5-.5h1a.5.5 0 01.5.5v2a.5.5 0 01-.5.5h-1a.5.5 0 01-.5-.5v-2zM7 15h10a1 1 0 110 2H7a1 1 0 110-2z" />
                </svg>
              </button>
              <button
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
                    d="M2 3.75A.75.75 0 012.75 3h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 3.75zm0 12.5A.75.75 0 012.75 15.5h14.5a.75.75 0 010 1.5H2.75a.75.75 0 01-.75-.75zM8.75 7.5a.75.75 0 000 1.5h8.5a.75.75 0 000-1.5h-8.5zM8 11.75a.75.75 0 01.75-.75h8.5a.75.75 0 010 1.5h-8.5a.75.75 0 01-.75-.75zM2.22 9.47a.75.75 0 011.06 0L5.03 11.22a.75.75 0 010 1.06l-1.75 1.75a.75.75 0 01-1.06-1.06l1.22-1.22-1.22-1.22a.75.75 0 010-1.06z"
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
                    d="M2 3.75A.75.75 0 012.75 3h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 3.75zm0 12.5A.75.75 0 012.75 15.5h14.5a.75.75 0 010 1.5H2.75a.75.75 0 01-.75-.75zM8.75 7.5a.75.75 0 000 1.5h8.5a.75.75 0 000-1.5h-8.5zM8 11.75a.75.75 0 01.75-.75h8.5a.75.75 0 010 1.5h-8.5a.75.75 0 01-.75-.75zM5.78 9.47a.75.75 0 010 1.06L4.56 11.75l1.22 1.22a.75.75 0 11-1.06 1.06L2.97 12.28a.75.75 0 010-1.06l1.75-1.75a.75.75 0 011.06 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <button
                type="button"
                data-toolbar-action="blockquote"
                class="btn btn-xs btn-ghost px-2"
                title={t("Blockquote")}
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
              </button>
              <button
                type="button"
                data-toolbar-action="codeBlock"
                class="btn btn-xs btn-ghost px-2"
                title={t("Code Block")}
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
              </button>
              <button
                type="button"
                data-toolbar-action="horizontalRule"
                class="btn btn-xs btn-ghost px-2"
                title={t("Horizontal Rule")}
              >
                &mdash;
              </button>
            </div>

            <div class="divider divider-horizontal mx-0.5 h-6"></div>

            <%!-- Undo/Redo + Clear Format --%>
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
          </div>
        <% end %>

        <%!-- Spacer --%>
        <div class="flex-1"></div>

        <%!-- Mode Switcher --%>
        <div class="flex items-center gap-0.5" data-mode-switcher>
          <div class="divider divider-horizontal mx-0.5 h-6"></div>
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

      <%!-- Visual Editor (contenteditable) --%>
      <div data-visual-wrapper class={["relative", @mode != :visual && "hidden"]}>
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
            "border border-base-300 rounded-lg overflow-y-auto p-4 pl-10",
            "focus:outline-2 focus:outline-primary/50 focus:-outline-offset-1",
            @readonly && "opacity-70 cursor-not-allowed"
          ]}
          style={"min-height: #{@height}"}
        >
          {raw(@visual_html)}
        </div>
      </div>

      <%!-- Markdown Mode: Plain textarea --%>
      <div data-markdown-wrapper class={[@mode != :markdown && "hidden"]}>
        <textarea
          id={"#{@id}-markdown-textarea"}
          class={[
            "textarea textarea-bordered w-full font-mono text-sm leading-relaxed",
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
          class={[
            "textarea textarea-bordered w-full font-mono text-sm leading-relaxed",
            @readonly && "opacity-70 cursor-not-allowed"
          ]}
          style={"min-height: #{@height}; resize: vertical;"}
          placeholder="<p>Write HTML here...</p>"
          readonly={@readonly}
          phx-debounce={@debounce}
        ><%= @visual_html %></textarea>
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

  # -- Helpers --

  defp t(string) do
    case Application.get_env(:leaf, :gettext_backend) do
      nil ->
        string

      backend ->
        Gettext.gettext(backend, string)
    end
  end

  defp markdown_to_html(nil), do: ""
  defp markdown_to_html(""), do: ""

  defp markdown_to_html(markdown) do
    case Earmark.as_html(markdown) do
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
    |> String.trim()
  end
end
