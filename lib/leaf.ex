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
                data-toolbar-action="code"
                class="btn btn-xs btn-ghost font-mono px-2"
                title={t("Inline Code")}
              >
                <.icon name="hero-code-bracket" class="w-3.5 h-3.5" />
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
                <.icon name="hero-link" class="w-3.5 h-3.5" />
              </button>
              <%= if :image in @toolbar do %>
                <button
                  type="button"
                  data-toolbar-action="insert-image"
                  class="btn btn-xs btn-ghost px-2"
                  title={t("Insert Image")}
                >
                  <.icon name="hero-photo" class="w-3.5 h-3.5" />
                </button>
              <% end %>
              <%= if :video in @toolbar do %>
                <button
                  type="button"
                  data-toolbar-action="insert-video"
                  class="btn btn-xs btn-ghost px-2"
                  title={t("Insert Video")}
                >
                  <.icon name="hero-video-camera" class="w-3.5 h-3.5" />
                </button>
              <% end %>
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
                <.icon name="hero-list-bullet" class="w-3.5 h-3.5" />
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
                <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
              </button>
              <button
                type="button"
                data-toolbar-action="redo"
                class="btn btn-xs btn-ghost px-2"
                title={t("Redo")}
              >
                <.icon name="hero-arrow-uturn-right" class="w-3.5 h-3.5" />
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
            <.icon name="hero-eye" class="w-3.5 h-3.5" />
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
      <div data-visual-wrapper class={[@mode != :visual && "hidden"]}>
        <div
          id={"#{@id}-visual"}
          data-editor-visual
          phx-update="ignore"
          contenteditable={if @readonly, do: "false", else: "true"}
          class={[
            "content-editor-visual",
            "border border-base-300 rounded-lg overflow-y-auto p-4",
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

    {:noreply, assign(socket, :content, markdown)}
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
