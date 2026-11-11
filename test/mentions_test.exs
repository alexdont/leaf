defmodule Leaf.MentionsTest do
  @moduledoc """
  Mention tokens (`@[type:id|Label]`, `#[type:id|Label]`) rendered as chips
  on the server's first paint, the same chip the client builds — so a page
  opens with "@Ada", not the token.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  @ada "01a0306e-577c-790e-971a-4e8dee4d3200"
  @person "@[user:#{@ada}|Ada Lovelace]"

  defp editor_html(content, opts \\ []) do
    render_component(Leaf, Keyword.merge([id: "mn", content: content, mentions: true], opts))
  end

  test "a token renders as a chip carrying its source" do
    html = editor_html("Hi #{@person} there")

    assert html =~ ~s(class="leaf-mention" contenteditable="false")
    assert html =~ ~s(data-leaf-mention-raw="#{@person}")
    assert html =~ ">@Ada Lovelace</span>"
  end

  test "a record token is a chip, not a hashtag" do
    html =
      editor_html("see #[project_task:#{@ada}|Q3 launch]",
        suggestions: [%{trigger: "#", label: "Tags"}]
      )

    assert html =~ ">#Q3 launch</span>"
    refute html =~ "leaf-hashtag"
  end

  test "off unless the host turns it on, and the flag reaches the client" do
    refute editor_html("Hi #{@person}", mentions: false) =~ "leaf-mention"
    assert editor_html("x") =~ ~s(data-mentions="true")
    assert editor_html("x", mentions: false) =~ ~s(data-mentions="false")
  end

  test "inside code a token is literal" do
    refute editor_html("`#{@person}`") =~ "leaf-mention"
  end

  test "a label with an ampersand is carried and shown as text" do
    html = editor_html("Hi @[user:#{@ada}|Smith & Co]")
    assert html =~ ~s(data-leaf-mention-raw="@[user:#{@ada}|Smith &amp; Co]")
    assert html =~ ">@Smith &amp; Co</span>"
  end
end
