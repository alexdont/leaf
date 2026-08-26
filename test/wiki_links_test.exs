defmodule Leaf.WikiLinksTest do
  @moduledoc """
  Obsidian-style `[[Target]]` links.

  Rendered as decoration spans, never `<a>`: `convertNode` serializes an
  unknown span as its own text, so the markdown stays `[[Target]]`. An anchor
  would serialize as `[label](href)` and rewrite every wiki link in the
  document into an ordinary markdown link.

  Rendering the component exercises the same mount → update → render path a
  `<.live_component>` caller goes through, which is where the decoration is
  applied.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  defp editor_html(content, opts \\ []) do
    render_component(
      Leaf,
      Keyword.merge([id: "wl", content: content, wiki_links: %{resolve: true}], opts)
    )
  end

  describe "opting in" do
    test "no wiki_links config leaves the brackets alone" do
      # A document using `[[…]]` for something else must be untouched.
      html = editor_html("see [[Ideas]]", wiki_links: nil)

      refute html =~ "leaf-wikilink"
    end

    test "the flag reaches the client" do
      assert editor_html("x") =~ ~s(data-wikilinks="true")
      assert editor_html("x", wiki_links: nil) =~ ~s(data-wikilinks="false")
    end
  end

  describe "the three shapes" do
    test "a plain target" do
      html = editor_html("see [[Ideas]] here")

      assert html =~ ~s(class="leaf-wikilink")
      assert html =~ ~s(data-leaf-wikilink="Ideas")
      assert html =~ ~s(data-leaf-wikilink-raw="[[Ideas]]")
      assert html =~ ">Ideas</span>"
    end

    test "an alias shows the alias and keeps the target" do
      html = editor_html("see [[Ideas|my notes]]")

      assert html =~ ~s(data-leaf-wikilink="Ideas")
      assert html =~ ">my notes</span>"
      # The raw source rides along so the client can serialize it back.
      assert html =~ ~s(data-leaf-wikilink-raw="[[Ideas|my notes]]")
    end

    test "a heading is carried separately from the target" do
      html = editor_html("see [[Ideas#Later]]")

      assert html =~ ~s(data-leaf-wikilink="Ideas")
      assert html =~ ~s(data-leaf-wikilink-heading="Later")
    end

    test "a path-qualified target keeps its slashes" do
      assert editor_html("see [[research/Ideas]]") =~ ~s(data-leaf-wikilink="research/Ideas")
    end
  end

  describe "what must not be touched" do
    test "brackets inside code stay literal" do
      # Inside `code` the brackets are text, not a link — the same rule
      # hashtags follow.
      html = editor_html("literal `[[NotALink]]` here")

      refute html =~ "leaf-wikilink"
    end

    test "an ordinary markdown link is left alone" do
      html = editor_html("[text](https://example.com)")

      refute html =~ "leaf-wikilink"
      assert html =~ "https://example.com"
    end

    test "a single bracket pair is not a wiki link" do
      refute editor_html("an [array] index") =~ "leaf-wikilink"
    end

    test "an empty target is not a link" do
      refute editor_html("see [[]] here") =~ "leaf-wikilink"
    end
  end

  describe "escaping" do
    test "a target containing markup cannot inject attributes" do
      html = editor_html(~s(see [[Ide"as]]))

      refute html =~ ~s(data-leaf-wikilink="Ide"as")
      assert html =~ "&quot;"
    end
  end
end
