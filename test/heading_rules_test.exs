defmodule Leaf.HeadingRulesTest do
  @moduledoc """
  Pins the hybrid editor's client-side heading detection against what the
  server actually renders.

  The hybrid preview decides "is this block a heading?" in JavaScript, and
  the published page decides it again in MDEx. When those two disagree the
  failure is invisible until it destroys content: a `#hashtag` at the start
  of a line used to preview as `<h1>hashtag</h1>` on the client, so leaving
  the block serialized it back out as a real `# hashtag` heading and the tag
  was gone.

  Leaf has no JavaScript test harness, so rather than stand one up this
  reads the two regexes straight out of the shipped bundle, compiles them
  with `:re` (both are plain PCRE — `{1,6}`, a negative lookahead and a
  character class) and runs them against the same table as the server. Any
  future edit that loosens them fails here.
  """
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket

  @bundle Path.join(__DIR__, "../priv/static/assets/leaf.js")
  @external_resource @bundle

  # Every block whose source starts with these is a heading in BOTH engines.
  @headings [
    {"# Todo", 1},
    {"## Todo", 2},
    {"### Todo", 3},
    {"#### Todo", 4},
    {"##### Todo", 5},
    {"###### Todo", 6},
    {"# ", 1},
    {"#\tTab separated", 1}
  ]

  # Blocks that must stay plain paragraphs in BOTH engines. The `#word`
  # entries are the hashtag cases this whole guard exists for.
  @paragraphs [
    "#dfdfd",
    "#elixir",
    "#новости",
    "##h",
    "####### seven hashes",
    "see #elixir mid-line",
    "#elixir trailing text"
  ]

  # A line holding nothing but hashes is the one deliberate disagreement.
  # CommonMark (and therefore MDEx) counts it as an empty heading; the
  # client refuses, because accepting it made every hashtag flash into h1
  # styling on its first keystroke and back out on the second. An empty
  # heading renders nothing either way, so the divergence is invisible —
  # but it is a choice, and it is recorded here rather than discovered.
  @client_only_paragraphs ["#", "##", "######"]

  describe "client-side heading regexes" do
    test "both require a space or tab after the hashes" do
      # Spelled out rather than pattern-matched so the diff is obvious when
      # someone changes them. Two shapes that must NOT come back:
      #
      #   ^(#{1,6})(?!#)( ?)       separator optional  -> `#tag` became h1
      #   ^(#{1,6})(?!#)([ \t]|$)  end-of-block counts -> `#` flashed as h1
      assert [~S<^(#{1,6})(?!#)[ \t]>, ~S<^(#{1,6})(?!#)[ \t](.*)$>] == js_heading_regexes()
    end

    test "detects the same headings the server does" do
      [scan, render] = compiled_js_heading_regexes()

      for {markdown, level} <- @headings do
        assert Regex.match?(scan, markdown),
               "client scan missed heading #{inspect(markdown)}"

        assert Regex.match?(render, markdown),
               "client render missed heading #{inspect(markdown)}"

        assert [level_hashes] = Regex.run(scan, markdown, capture: :all_but_first) |> Enum.take(1)
        assert String.length(level_hashes) == level

        assert server_heading_level(markdown) == level,
               "server disagreed about #{inspect(markdown)}"
      end
    end

    test "leaves the same paragraphs alone the server does" do
      [scan, render] = compiled_js_heading_regexes()

      for markdown <- @paragraphs do
        refute Regex.match?(scan, markdown),
               "client scan wrongly treated #{inspect(markdown)} as a heading"

        refute Regex.match?(render, markdown),
               "client render wrongly treated #{inspect(markdown)} as a heading"

        assert server_heading_level(markdown) == nil,
               "server wrongly treated #{inspect(markdown)} as a heading"
      end
    end

    test "a bare hash run is the one documented divergence" do
      [scan, render] = compiled_js_heading_regexes()

      for markdown <- @client_only_paragraphs do
        refute Regex.match?(scan, markdown),
               "client should not style a bare #{inspect(markdown)} as a heading"

        refute Regex.match?(render, markdown)

        # The server still follows CommonMark here — an EMPTY heading, so
        # nothing is visible on the page and no text can be lost.
        assert server_heading_level(markdown) == String.length(markdown)
        assert server_html(markdown) =~ ~r{<h#{String.length(markdown)}>\s*</h}
      end
    end
  end

  # -- helpers --

  # Pull the heading regexes out of the shipped bundle in file order:
  # `_scanSource` first, then `_renderBlockFromSource`.
  defp js_heading_regexes do
    sources =
      @bundle
      |> File.read!()
      |> then(&Regex.scan(~r{var headingMatch = text\.match\(/(.+?)/\);}, &1))
      |> Enum.map(fn [_full, source] -> source end)

    assert_two!(sources)
    sources
  end

  defp compiled_js_heading_regexes do
    Enum.map(js_heading_regexes(), &Regex.compile!/1)
  end

  defp assert_two!([_scan, _render]), do: :ok

  defp assert_two!(other) do
    raise """
    expected exactly 2 heading regexes in leaf.js (_scanSource and
    _renderBlockFromSource), found #{length(other)}: #{inspect(other)}

    If the detection moved or was renamed, update this test's extraction —
    do not delete it. It is the only thing keeping the client's idea of a
    heading aligned with the server's.
    """
  end

  # What leaf's own server-side rendering makes of a single block.
  defp server_html(markdown) do
    socket = %Socket{
      assigns: %{
        __changed__: %{},
        id: "editor-1",
        mode: :hybrid,
        content: "",
        visual_html: "",
        deny: []
      }
    }

    {:ok, updated} = Leaf.update(%{action: :set_content, content: markdown}, socket)
    updated.assigns.visual_html
  end

  defp server_heading_level(markdown) do
    case Regex.run(~r{^<h([1-6])[ >]}, String.trim_leading(server_html(markdown))) do
      [_, level] -> String.to_integer(level)
      nil -> nil
    end
  end
end
