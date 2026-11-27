defmodule Leaf.CspTest do
  @moduledoc """
  GitHub issue #9: Leaf under a nonce-based Content-Security-Policy.

  - `style_nonce` nonces the inline `<style>`; without it the block keeps
    `script_nonce`, as before.
  - With a `style_nonce` the editor's inline `style` attributes, which such a
    policy blocks, go out as `data-leaf-style` (applied by the hook). Without
    one the markup is unchanged.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defp html(opts),
    do:
      render_component(
        Leaf,
        Keyword.merge([id: "editor-1", content: "hi", save_status: :saved], opts)
      )

  defp tag_nonces(html, tag),
    do: Regex.scan(~r{<#{tag} nonce="([^"]*)"}, html, capture: :all_but_first) |> List.flatten()

  # `style="` inside the inline <style>/<script> bodies is CSS/JS text, not
  # an attribute: only the markup counts.
  defp markup(html), do: String.replace(html, ~r{<(style|script)\b.*?</\1>}s, "")

  test "script_nonce alone still nonces both inline tags" do
    h = html(script_nonce: "N1")
    assert tag_nonces(h, "style") == ["N1"]
    assert tag_nonces(h, "script") == ["N1"]
  end

  test "style_nonce nonces the <style>; the <script> keeps script_nonce" do
    h = html(script_nonce: "SCR", style_nonce: "STY")
    assert tag_nonces(h, "style") == ["STY"]
    assert tag_nonces(h, "script") == ["SCR"]
  end

  test "without a style_nonce the inline styles are plain style attributes, as before" do
    m = markup(html(script_nonce: "N1"))
    assert m =~ ~s(style="container-type: inline-size; container-name: leaf-editor;")
    assert m =~ ~s(style="display:none")
    refute m =~ "data-leaf-style"
  end

  test "with a style_nonce no style attribute is rendered; each moves to data-leaf-style" do
    plain = markup(html([]))
    strict = markup(html(style_nonce: "STY"))

    refute strict =~ ~r/\sstyle="/

    assert length(Regex.scan(~r/\sdata-leaf-style="/, strict)) ==
             length(Regex.scan(~r/\sstyle="/, plain))

    assert strict =~
             ~s(data-leaf-style="container-type: inline-size; container-name: leaf-editor;")

    assert strict =~ ~s(data-leaf-style="min-height: )
  end

  test "an empty style_nonce counts as none" do
    refute markup(html(style_nonce: "")) =~ "data-leaf-style"
  end
end
