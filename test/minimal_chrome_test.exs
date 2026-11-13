defmodule Leaf.MinimalChromeTest do
  @moduledoc """
  `chrome={:minimal}`: the hybrid surface with nothing around it — no
  toolbar, switcher, counters or border — plus a badge, and Enter submits.
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

  describe "chrome={:minimal}" do
    setup do
      %{html: editor_html(content: "hi", chrome: :minimal)}
    end

    test "draws no toolbar, switcher or counters", %{html: html} do
      refute html =~ "data-visual-toolbar"
      refute html =~ "data-mobile-toolbar"
      refute html =~ "data-mode-tab="
      refute html =~ "data-word-count"
      refute html =~ "border-base-300"
    end

    test "is a hybrid editor that submits on Enter, with no selection bubble", %{html: html} do
      assert html =~ ~s(data-mode="hybrid")
      assert html =~ ~s(data-leaf-chrome="minimal")
      assert html =~ ~s(data-submit-on-enter="true")
      assert html =~ ~s(data-toolbar-layout="fixed")
    end

    test "grows with the text", %{html: html} do
      assert html =~ ~s(data-height="auto")
    end

    test "shows the leaf badge bottom right", %{html: html} do
      assert [_, "leaf"] = Regex.run(~r{data-leaf-badge[^>]*>\s*([^<]*?)\s*<}, html)
    end
  end

  test "the badge text is the host's, and can be turned off" do
    assert editor_html(chrome: :minimal, badge: "task") =~ ~r{data-leaf-badge[^>]*>\s*task\s*<}
    refute editor_html(chrome: :minimal, badge: nil) =~ "data-leaf-badge"
    refute editor_html(chrome: :minimal, badge: "") =~ "data-leaf-badge"
  end

  test "ignores a mode or floating toolbar the host passes" do
    html = editor_html(chrome: :minimal, mode: :markdown, toolbar_layout: :floating)
    assert html =~ ~s(data-mode="hybrid")
    assert html =~ ~s(data-toolbar-layout="fixed")
  end

  test "an explicit height or submit_on_enter wins" do
    html = editor_html(chrome: :minimal, height: "80px", submit_on_enter: false)
    assert html =~ ~s(data-height="80px")
    assert html =~ ~s(data-submit-on-enter="false")
  end

  test "denying hybrid mode with it raises" do
    assert_raise ArgumentError, ~r/hybrid/, fn ->
      editor_html(chrome: :minimal, deny: [:hybrid_mode])
    end
  end

  test "the full chrome is unchanged: toolbar, footer, 480px, no badge, Enter is a newline" do
    html = editor_html(content: "hi")
    assert html =~ "data-visual-toolbar"
    assert html =~ "data-word-count"
    assert html =~ ~s(data-height="480px")
    assert html =~ ~s(data-leaf-chrome="full")
    assert html =~ ~s(data-submit-on-enter="false")
    refute html =~ "data-leaf-badge"
  end

  test "submit_on_enter works with the full chrome too" do
    assert editor_html(submit_on_enter: true) =~ ~s(data-submit-on-enter="true")
  end

  test "the submit event reaches the parent as {:leaf_submit, …}, sanitized" do
    socket = %Socket{
      assigns: %{__changed__: %{}, id: "editor-1", deny: [:links], notify: nil}
    }

    assert {:noreply, _} =
             Leaf.handle_event(
               "submit",
               %{"markdown" => "Buy [milk](https://x.test)", "html" => "<p>Buy milk</p>"},
               socket
             )

    assert_received {:leaf_submit,
                     %{editor_id: "editor-1", markdown: md, html: "<p>Buy milk</p>"}}

    refute md =~ "](https://x.test)"
  end
end
