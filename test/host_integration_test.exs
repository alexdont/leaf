defmodule Leaf.HostIntegrationTest do
  @moduledoc """
  The seams a host LiveView drives: flush correlation, programmatic
  content replacement, toolbar_extra placement and hashtag decoration.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket

  defp editor_html(opts) do
    opts
    |> Keyword.put_new(:id, "editor-1")
    |> then(&render_component(Leaf, &1))
    |> String.replace(~r{<(style|script)\b.*?</\1>}s, "")
  end

  defp socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}, id: "editor-1", deny: []}, Map.new(assigns))
    }
  end

  describe "flush correlation" do
    test "a bare flush carries no ref, exactly as before" do
      assert {:ok, updated} = Leaf.update(%{action: :flush}, socket([]))
      assert %{action: "flush", ref: nil} = last_command(updated)
    end

    test "a ref is passed through to the client verbatim" do
      assert {:ok, updated} = Leaf.update(%{action: :flush, ref: "save-42"}, socket([]))
      assert %{action: "flush", ref: "save-42"} = last_command(updated)
    end

    test "the client's reply becomes an identifiable {:leaf_flushed, …}" do
      assert {:noreply, _} =
               Leaf.handle_event(
                 "flushed",
                 %{"ref" => "save-42", "markdown" => "# hi", "html" => "<h1>hi</h1>"},
                 socket([])
               )

      assert_received {:leaf_flushed,
                       %{
                         editor_id: "editor-1",
                         ref: "save-42",
                         markdown: "# hi",
                         html: "<h1>hi</h1>"
                       }}
    end

    test "the flushed payload is sanitized like any other content" do
      assert {:noreply, _} =
               Leaf.handle_event(
                 "flushed",
                 %{
                   "ref" => 1,
                   "markdown" => "[docs](https://example.com)",
                   "html" => ~s(<a href="https://example.com">docs</a>)
                 },
                 socket(deny: [:links])
               )

      assert_received {:leaf_flushed, %{markdown: markdown, html: html}}
      refute markdown =~ "https://example.com"
      refute html =~ "<a "
    end
  end

  describe "set_content" do
    test "tells the client to re-baseline its dirty snapshot by default" do
      assert {:ok, updated} =
               Leaf.update(%{action: :set_content, content: "# v2"}, socket(preserve_tags: []))

      assert %{action: "set_content", mark_saved: true} = last_command(updated)
    end

    test "mark_saved: false keeps the old baseline" do
      assert {:ok, updated} =
               Leaf.update(
                 %{action: :set_content, content: "# v2", mark_saved: false},
                 socket(preserve_tags: [])
               )

      assert %{mark_saved: false} = last_command(updated)
    end
  end

  describe "toolbar_extra" do
    test "buttons collapse into the overflow menu by default" do
      html = editor_html(content: "", toolbar_extra: [%{id: "hero", label: "Hero"}])

      assert html =~ ~s(data-toolbar-overflow="extra")
      refute html =~ "data-toolbar-extra-pinned"
    end

    test "collapse: false pins a button to the main row and out of the menu" do
      html =
        editor_html(
          content: "",
          toolbar_extra: [%{id: "hero", label: "Hero", collapse: false}]
        )

      assert html =~ "data-toolbar-extra-pinned"
      # No mirror row in the compact menu — it never collapses, so listing
      # it there would just duplicate it.
      refute html =~ ~s(data-compact-overflow="extra")
    end

    test "a mixed list splits into both groups" do
      html =
        editor_html(
          content: "",
          toolbar_extra: [
            %{id: "hero", label: "Hero", collapse: false},
            %{id: "note", label: "Note"}
          ]
        )

      assert html =~ "data-toolbar-extra-pinned"
      assert html =~ ~s(data-toolbar-overflow="extra")
      assert html =~ ~s(data-host-action="hero")
      assert html =~ ~s(data-host-action="note")
    end
  end

  describe "hashtag decoration" do
    test "is off unless the host configured a # trigger" do
      html = editor_html(content: "A #tag here.")

      refute html =~ "leaf-hashtag"
      assert html =~ ~s(data-hashtags="false")
    end

    test "wraps hashtags when # is a configured trigger" do
      html = editor_html(content: "A #tag here.", suggestions: [%{trigger: "#"}])

      assert html =~ ~s(data-hashtags="true")
      assert html =~ ~s(<span class="leaf-hashtag">#tag</span>)
    end

    test "leaves headings alone" do
      html = editor_html(content: "# Heading", suggestions: [%{trigger: "#"}])

      assert html =~ "<h1>Heading</h1>"
      refute html =~ "leaf-hashtag"
    end

    # The chip's `data-leaf-raw` holds the verbatim source. Decorating a
    # `#` in there would corrupt the one thing the round trip depends on.
    test "never touches a preserved tag's raw source" do
      html =
        editor_html(
          content: ~s|<Note tag="#elixir">body</Note>|,
          preserve_tags: ["Note"],
          suggestions: [%{trigger: "#"}]
        )

      assert html =~ ~s(data-leaf-raw="&lt;Note tag=&quot;#elixir&quot;&gt;body&lt;/Note&gt;")
      refute html =~ ~s(&quot;<span class="leaf-hashtag">)
    end

    test "leaves URL fragments and code alone" do
      html =
        editor_html(
          content: "See [docs](/page#section) and `#literal` here.",
          suggestions: [%{trigger: "#"}]
        )

      refute html =~ "leaf-hashtag"
    end
  end

  describe "bundle-presence check" do
    test "is emitted by default" do
      html =
        Leaf
        |> render_component(id: "editor-1", content: "")
        |> to_string()

      assert html =~ "__leafBundleCheck"
    end

    # The only inline <script> Leaf emits. A host under a CSP that forbids
    # inline scripts and cannot supply a nonce needs a way out that does
    # not cost it anything else.
    test "bundle_check={false} emits no inline script at all" do
      html =
        Leaf
        |> render_component(id: "editor-1", content: "", bundle_check: false)
        |> to_string()

      refute html =~ "__leafBundleCheck"
      refute html =~ "<script"
      # ...and the editor itself is untouched.
      assert html =~ ~s(phx-hook="Leaf")
      assert html =~ ~s(data-leaf-js-version=)
    end
  end

  describe "suggestion boundaries" do
    test ":not_line_start reaches the client" do
      html =
        editor_html(
          content: "",
          suggestions: [%{trigger: "#", boundary: :not_line_start}]
        )

      assert html =~ ~s(data-boundary="not_line_start")
    end

    test "an unknown boundary still falls back to word_start" do
      html = editor_html(content: "", suggestions: [%{trigger: "#", boundary: :nonsense}])

      assert html =~ ~s(data-boundary="word_start")
    end
  end

  # push_event/3 queues commands in the socket's private `live_temp` as
  # [name, payload] pairs; dig the last payload out rather than repeating
  # that internal shape at every call site.
  defp last_command(%Socket{} = socket) do
    socket.private
    |> Map.get(:live_temp, %{})
    |> Map.get(:push_events, [])
    |> List.last()
    |> case do
      [_name, payload] -> payload
      _ -> flunk("no pushed event found: #{inspect(socket.private)}")
    end
  end
end
