defmodule LeafTest do
  use ExUnit.Case
  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket

  test "module can be loaded" do
    assert Code.ensure_loaded?(Leaf)
  end

  test "leaf_editor component renders basic markup" do
    rendered =
      render_component(&Leaf.leaf_editor/1,
        id: "editor-1",
        content: "",
        mode: :visual
      )

    assert rendered =~ "phx-hook=\"Leaf\""
    assert rendered =~ "data-editor-id=\"editor-1\""
  end

  # Regression for 0.2.24: the :class attr default (added in 0.2.23) was only
  # filled in for function-component calls (<.leaf_editor />). The matching
  # mount/1 assign_new was missed, so <.live_component module={Leaf}> callers
  # who omitted class= crashed with `KeyError: key :class not found` on first
  # render. Rendering the component directly exercises the mount/1 -> update/2
  # -> render/1 path that live_component uses.
  test "renders via live_component path with no attrs beyond :id" do
    html = render_component(Leaf, id: "t")

    assert html =~ ~s(id="t")
    assert html =~ "min-w-0"
  end

  test "content_changed strips denied links and images" do
    socket = base_socket(deny: [:links, :images])

    html = ~s(<p>See <a href="https://example.com">docs</a> <img src="/x.png" alt="x"></p>)
    markdown = "See [docs](https://example.com) ![x](/x.png)"

    assert {:noreply, new_socket} =
             Leaf.handle_event(
               "content_changed",
               %{"markdown" => markdown, "html" => html},
               socket
             )

    assert_received {:leaf_changed,
                     %{editor_id: "editor-1", markdown: pushed_md, html: pushed_html}}

    refute pushed_md =~ "[docs](https://example.com)"
    refute pushed_md =~ "![x](/x.png)"
    refute pushed_html =~ ~r/<a\b/i
    refute pushed_html =~ ~r/<img\b/i

    assert new_socket.assigns.content == pushed_md
    assert new_socket.assigns.visual_html == pushed_html
  end

  test "markdown_content_changed sanitizes denied markdown and generated html" do
    socket = base_socket(deny: [:links, :images])
    markdown = "Visit [docs](https://example.com) and ![x](/x.png)"

    assert {:noreply, new_socket} =
             Leaf.handle_event("markdown_content_changed", %{"content" => markdown}, socket)

    assert_received {:leaf_changed, %{markdown: pushed_md, html: pushed_html}}
    refute pushed_md =~ "[docs](https://example.com)"
    refute pushed_md =~ "![x](/x.png)"
    refute pushed_html =~ ~r/<a\b/i
    refute pushed_html =~ ~r/<img\b/i
    assert new_socket.assigns.content == pushed_md
  end

  test "html_content_changed sanitizes denied html" do
    socket = base_socket(deny: [:links, :images], content: "safe")
    html = ~s(<p><a href="https://example.com">docs</a><img src="/x.png" alt="x"></p>)

    assert {:noreply, new_socket} =
             Leaf.handle_event("html_content_changed", %{"content" => html}, socket)

    assert_received {:leaf_changed, %{markdown: "safe", html: pushed_html}}
    refute pushed_html =~ ~r/<a\b/i
    refute pushed_html =~ ~r/<img\b/i
    assert new_socket.assigns.visual_html == pushed_html
  end

  test "set_content sanitizes markdown before assigning content" do
    socket = base_socket(deny: [:links, :images])
    content = "See [docs](https://example.com) ![x](/x.png)"

    assert {:ok, new_socket} =
             Leaf.update(%{action: :set_content, content: content}, socket)

    refute new_socket.assigns.content =~ "[docs](https://example.com)"
    refute new_socket.assigns.content =~ "![x](/x.png)"
  end

  test "set_content keeps image markdown when only links are denied" do
    socket = base_socket(deny: [:links])
    content = "See [docs](https://example.com) ![x](/x.png)"

    assert {:ok, new_socket} =
             Leaf.update(%{action: :set_content, content: content}, socket)

    refute new_socket.assigns.content =~ "[docs](https://example.com)"
    assert new_socket.assigns.content =~ "![x](/x.png)"
  end

  describe "apply_operation" do
    test "pushes the new document, its html, and the splice that produced it" do
      socket = base_socket(content: "hello")

      assert {:ok, new_socket} =
               Leaf.update(
                 %{
                   action: :apply_operation,
                   content: "hello there",
                   op: %{at: 5, remove: 0, insert: " there"}
                 },
                 socket
               )

      assert [["leaf-remote-operation:editor-1", payload]] =
               new_socket.private.live_temp.push_events

      # The client needs all three: the html because markdown->html only
      # happens here, and the splice because that is what tells it where the
      # caret should end up.
      assert payload.content == "hello there"
      assert payload.html =~ "hello there"
      assert %{at: 5, remove: 0, insert: " there"} = payload

      assert new_socket.assigns.content == "hello there"
    end

    test "carries the rendered splice through to the client" do
      socket = base_socket(content: "hello")

      assert {:ok, new_socket} =
               Leaf.update(
                 %{
                   action: :apply_operation,
                   content: "hello!",
                   op: %{
                     at: 5,
                     remove: 0,
                     insert: "!",
                     rendered: %{at: 5, remove: 0, insert: "!"}
                   }
                 },
                 socket
               )

      assert [["leaf-remote-operation:editor-1", payload]] =
               new_socket.private.live_temp.push_events

      assert payload.rendered == %{at: 5, remove: 0, insert: "!"}
    end

    test "an operation without a rendered splice is still applied" do
      socket = base_socket(content: "hello")

      assert {:ok, new_socket} =
               Leaf.update(
                 %{
                   action: :apply_operation,
                   content: "hello!",
                   op: %{at: 5, remove: 0, insert: "!"}
                 },
                 socket
               )

      assert [["leaf-remote-operation:editor-1", payload]] =
               new_socket.private.live_temp.push_events

      assert payload.rendered == nil
    end

    test "sanitizes the incoming document the same way set_content does" do
      socket = base_socket(deny: [:links, :images])

      assert {:ok, new_socket} =
               Leaf.update(
                 %{
                   action: :apply_operation,
                   content: "See [docs](https://example.com) ![x](/x.png)",
                   op: %{at: 0, remove: 0, insert: "See "}
                 },
                 socket
               )

      refute new_socket.assigns.content =~ "[docs](https://example.com)"
      refute new_socket.assigns.visual_html =~ ~r/<a\b/i
    end
  end

  test "deny flags are exposed for toolbar actions" do
    rendered =
      render_component(&Leaf.leaf_editor/1,
        id: "editor-1",
        content: "",
        mode: :visual,
        preset: :advanced,
        toolbar: [:image, :video],
        deny: [:links, :images, :video]
      )

    assert rendered =~ ~s(data-deny-links="true")
    assert rendered =~ ~s(data-deny-images="true")
    assert rendered =~ ~s(data-deny-video="true")
    refute rendered =~ ~s(data-toolbar-action="link")
    refute rendered =~ ~s(data-toolbar-action="insert-image")
    refute rendered =~ ~s(data-toolbar-action="insert-video")
  end

  test "deny mode flags are exposed to the client" do
    rendered =
      render_component(&Leaf.leaf_editor/1,
        id: "editor-1",
        content: "",
        mode: :visual,
        deny: [:markdown_mode, :html_mode]
      )

    assert rendered =~ ~s(data-deny-markdown-mode="true")
    assert rendered =~ ~s(data-deny-html-mode="true")
  end

  # Defensive path only — a denied mode has no tab to click, so the client
  # cannot normally report one. The fallback is the first *allowed* mode
  # rather than a hardcoded :visual, which stopped being a safe default
  # once :visual itself became deniable.
  test "mode_changed falls back to the first allowed mode when the requested one is denied" do
    socket = base_socket(deny: [:html_mode], mode: :visual)

    assert {:noreply, new_socket} =
             Leaf.handle_event("mode_changed", %{"mode" => "html", "content" => "x"}, socket)

    assert_received {:leaf_mode_changed, %{mode: :hybrid}}
    assert new_socket.assigns.mode == :hybrid
  end

  test "the operation event forwards the rendered splice to the host" do
    socket = base_socket([])

    assert {:noreply, _} =
             Leaf.handle_event(
               "operation",
               %{
                 "at" => 3,
                 "remove" => 1,
                 "insert" => "z",
                 "rendered" => %{"at" => 3, "remove" => 1, "insert" => "z"}
               },
               socket
             )

    assert_received {:leaf_operation, %{rendered: %{at: 3, remove: 1, insert: "z"}}}
  end

  test "an operation without a rendered splice reaches the host as nil" do
    socket = base_socket([])

    assert {:noreply, _} =
             Leaf.handle_event("operation", %{"at" => 3, "remove" => 1, "insert" => "z"}, socket)

    assert_received {:leaf_operation, %{rendered: nil}}
  end

  describe "inline suggestions" do
    test "no suggestion markup when the host configures none" do
      rendered = render_component(&Leaf.leaf_editor/1, id: "editor-1", content: "")

      refute rendered =~ "data-leaf-suggestions"
      refute rendered =~ "data-leaf-suggest"
    end

    test "trigger config renders with defaults filled in" do
      rendered =
        render_component(&Leaf.leaf_editor/1,
          id: "editor-1",
          content: "",
          suggestions: [%{trigger: "#", label: "Tags", allow_create: true}]
        )

      assert rendered =~ "data-leaf-suggestions"
      assert rendered =~ ~s(data-trigger="#")
      assert rendered =~ ~s(data-label="Tags")
      assert rendered =~ ~s(data-allow-create="true")
      assert rendered =~ ~s(data-boundary="word_start")
      assert rendered =~ ~s(data-min-chars="0")
      assert rendered =~ ~s(data-debounce="150")
      assert rendered =~ ~s(data-max-results="10")
      assert rendered =~ ~s(data-exclude="code,link")
    end

    test "token/first_char accept a Regex or a raw character class" do
      rendered =
        render_component(&Leaf.leaf_editor/1,
          id: "editor-1",
          content: "",
          suggestions: [%{trigger: "@", token: ~r/[a-z0-9_]/u, first_char: "[a-z]"}]
        )

      assert rendered =~ ~s(data-token="[a-z0-9_]")
      assert rendered =~ ~s(data-first-char="[a-z]")
    end

    test "string keys work and entries without a trigger are dropped" do
      rendered =
        render_component(&Leaf.leaf_editor/1,
          id: "editor-1",
          content: "",
          suggestions: [%{"trigger" => "/", "label" => "Components"}, %{label: "nope"}]
        )

      assert rendered =~ ~s(data-trigger="/")
      assert rendered =~ ~s(data-label="Components")
      refute rendered =~ ~s(data-label="nope")
    end

    test "multiple triggers survive normalization in order" do
      configs = Leaf.normalized_suggestions([%{trigger: "#"}, %{trigger: "@"}])

      assert Enum.map(configs, & &1.trigger) == ["#", "@"]
    end

    test "an explicit empty insert_suffix is kept, a missing one defaults to a space" do
      assert [%{insert_suffix: ""}] =
               Leaf.normalized_suggestions([%{trigger: "#", insert_suffix: ""}])

      assert [%{insert_suffix: " "}] = Leaf.normalized_suggestions([%{trigger: "#"}])
    end

    test "suggest event forwards trigger, query and seq to the host" do
      socket = base_socket([])

      assert {:noreply, _socket} =
               Leaf.handle_event(
                 "suggest",
                 %{"trigger" => "#", "query" => "eli", "seq" => 7},
                 socket
               )

      assert_received {:leaf_suggest,
                       %{editor_id: "editor-1", trigger: "#", query: "eli", seq: 7}}
    end

    test ":suggestions reply echoes the request and normalizes results" do
      socket = base_socket([])

      assert {:ok, new_socket} =
               Leaf.update(
                 %{
                   action: :suggestions,
                   trigger: "#",
                   query: "eli",
                   seq: 7,
                   results: [
                     %{value: "elixir", label: "#elixir", sublabel: "12 posts"},
                     "phoenix",
                     %{"label" => "erlang", "icon" => "hero-hashtag"},
                     %{sublabel: "no value at all"}
                   ]
                 },
                 socket
               )

      assert [["leaf-suggestions:editor-1", payload]] =
               new_socket.private.live_temp.push_events

      assert %{trigger: "#", query: "eli", seq: 7} = payload

      assert payload.results == [
               %{value: "elixir", label: "#elixir", sublabel: "12 posts", icon: ""},
               %{value: "phoenix", label: "phoenix", sublabel: "", icon: ""},
               %{value: "erlang", label: "erlang", sublabel: "", icon: "hero-hashtag"}
             ]
    end
  end

  defp base_socket(opts) do
    %Socket{
      assigns: %{
        __changed__: %{},
        id: "editor-1",
        mode: Keyword.get(opts, :mode, :visual),
        content: Keyword.get(opts, :content, ""),
        visual_html: Keyword.get(opts, :visual_html, ""),
        deny: Keyword.get(opts, :deny, [])
      }
    }
  end
end
