defmodule Leaf.DenyModesTest do
  @moduledoc """
  `deny` for editing modes is meant to be one rule, not a default a stray
  click can talk its way past — so these check every route into a mode:
  the three switchers' markup, the fallback when the host denies its own
  `mode:`, and the `:set_mode` command.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket

  # The inline <style>/<script> blocks mention the same data attributes the
  # markup does, so strip them before asserting on what was rendered.
  defp editor_html(opts) do
    opts
    |> Keyword.put_new(:id, "editor-1")
    |> then(&render_component(Leaf, &1))
    |> String.replace(~r{<(style|script)\b.*?</\1>}s, "")
  end

  defp socket(assigns) do
    %Socket{assigns: Map.merge(%{__changed__: %{}, id: "editor-1"}, Map.new(assigns))}
  end

  test "denied modes have no tab anywhere in the DOM" do
    html = editor_html(content: "hi", mode: :markdown, deny: [:visual_mode, :hybrid_mode])

    refute html =~ ~s(data-mode-tab="visual")
    refute html =~ ~s(data-mode-tab="hybrid")
    assert html =~ ~s(data-mode-tab="markdown")
    assert html =~ ~s(data-mode-tab="html")
  end

  # Regression: the compact and mobile switchers used to render markdown /
  # html tabs unconditionally, so denying a mode only hid its inline tab —
  # a narrow viewport was a way back in.
  test "the compact and mobile switchers honour the deny list too" do
    html = editor_html(content: "hi", deny: [:markdown_mode, :html_mode])

    refute html =~ ~s(data-mode-tab="markdown")
    refute html =~ ~s(data-mode-tab="html")
    # Three switchers, two allowed modes each.
    assert length(Regex.scan(~r/data-mode-tab="hybrid"/, html)) == 3
    assert length(Regex.scan(~r/data-mode-tab="visual"/, html)) == 3
  end

  test "a single surviving mode hides the switcher rather than showing a dead tab" do
    html =
      editor_html(
        content: "hi",
        mode: :markdown,
        deny: [:visual_mode, :hybrid_mode, :html_mode]
      )

    refute html =~ "data-mode-tab="
    refute html =~ ~s(data-mode-switcher="inline")
  end

  test "the deny state reaches the client" do
    html = editor_html(content: "hi", mode: :markdown, deny: [:visual_mode, :hybrid_mode])

    assert html =~ ~s(data-deny-visual-mode="true")
    assert html =~ ~s(data-deny-hybrid-mode="true")
    assert html =~ ~s(data-fallback-mode="markdown")
  end

  test "denying the requested mode falls back to the first allowed one" do
    # :hybrid is first in the preference order, so denying only :visual
    # lands there; denying both visual surfaces lands on markdown.
    assert editor_html(content: "", mode: :visual, deny: [:visual_mode]) =~ ~s(data-mode="hybrid")

    assert editor_html(content: "", mode: :visual, deny: [:visual_mode, :hybrid_mode]) =~
             ~s(data-mode="markdown")
  end

  test "denying every mode raises rather than rendering blank" do
    assert_raise ArgumentError, ~r/removes every editing mode/, fn ->
      editor_html(
        content: "",
        deny: [:visual_mode, :hybrid_mode, :markdown_mode, :html_mode]
      )
    end
  end

  describe ":set_mode command" do
    test "is ignored for a denied mode, leaving the current mode alone" do
      socket = socket(deny: [:visual_mode], mode: :markdown)

      assert {:ok, updated} = Leaf.update(%{action: :set_mode, mode: :visual}, socket)
      assert updated.assigns.mode == :markdown
    end

    test "still works for an allowed mode" do
      socket = socket(deny: [:visual_mode], mode: :markdown)

      assert {:ok, updated} = Leaf.update(%{action: :set_mode, mode: :hybrid}, socket)
      assert updated.assigns.mode == :hybrid
    end
  end
end
