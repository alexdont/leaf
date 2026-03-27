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

  test "deny flags hide link, image and video toolbar buttons" do
    rendered =
      render_component(&Leaf.leaf_editor/1,
        id: "editor-1",
        content: "",
        mode: :visual,
        preset: :advanced,
        toolbar: [:image, :video],
        deny: [:links, :images, :video]
      )

    refute rendered =~ ~s(data-toolbar-action="link")
    refute rendered =~ ~s(data-toolbar-action="insert-image")
    refute rendered =~ ~s(data-toolbar-action="insert-video")
  end

  test "deny flags hide markdown and html mode tabs" do
    rendered =
      render_component(&Leaf.leaf_editor/1,
        id: "editor-1",
        content: "",
        mode: :visual,
        deny: [:markdown_mode, :html_mode]
      )

    refute rendered =~ ~s(data-mode-tab="markdown")
    refute rendered =~ ~s(data-mode-tab="html")
    assert rendered =~ ~s(data-mode-tab="visual")
  end

  test "mode_changed falls back to visual when requested mode is denied" do
    socket = base_socket(deny: [:html_mode], mode: :visual)

    assert {:noreply, new_socket} =
             Leaf.handle_event("mode_changed", %{"mode" => "html", "content" => "x"}, socket)

    assert_received {:leaf_mode_changed, %{mode: :visual}}
    assert new_socket.assigns.mode == :visual
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
