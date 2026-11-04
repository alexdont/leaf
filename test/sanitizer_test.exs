defmodule Leaf.SanitizerTest do
  @moduledoc """
  Raw HTML in markdown reaches the visual surface as HTML — Leaf writes
  figures, details and sized images that way itself — so the renderer runs
  with `unsafe: true`. Everything it lets through passes this allow-list
  first, or a `<script>`, an `onerror` or a `javascript:` link typed by one
  collaborator would run in every other one's browser.
  """
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Leaf.Sanitizer
  alias Phoenix.LiveView.Socket

  # The editing surface alone: the markdown itself rides along in a data
  # attribute, so the whole page would still contain the attack as text.
  defp surface(markdown) do
    html = render_component(Leaf, id: "s", content: markdown)
    [_, inner] = Regex.run(~r/id="s-visual"[^>]*>(.*?)<\/div>/s, html)
    inner
  end

  describe "html/1" do
    test "drops scripts, handlers and executable URLs" do
      out =
        Sanitizer.html(
          ~s|<p><script>x()</script><img src="x" onerror="alert(1)"><a href="javascript:alert(1)">j</a><a href="data:text/html,x">d</a></p>|
        )

      refute out =~ "<script"
      refute out =~ "onerror"
      refute out =~ "javascript:"
      refute out =~ "data:"
      assert out =~ ~s(<img src="x">)
      assert out =~ "<a>j</a>"
    end

    test "keeps what Leaf writes itself" do
      out =
        Sanitizer.html(
          ~s(<figure data-align="left"><img src="/a.png" width="20" height="10" data-align="left" draggable="true"><figcaption>c</figcaption></figure>) <>
            ~s(<details open><summary>s</summary>b</details><p><sup>1</sup><sub>2</sub><u>u</u><mark>m</mark><kbd>k</kbd>) <>
            ~s(<span class="leaf-spoiler" contenteditable="false" data-leaf-raw="&lt;Hero/&gt;">sp</span></p>) <>
            ~s(<video src="/v.mp4" controls></video><a href="/rel">r</a><a href="#top">t</a><a href="mailto:a@b.c">m</a>)
        )

      for kept <- [
            ~s(<figure data-align="left">),
            ~s(width="20"),
            ~s(height="10"),
            ~s(draggable="true"),
            "<figcaption>c</figcaption>",
            "<details open",
            "<summary>s</summary>",
            "<sup>1</sup>",
            "<sub>2</sub>",
            "<u>u</u>",
            "<mark>m</mark>",
            "<kbd>k</kbd>",
            ~s(class="leaf-spoiler"),
            ~s(contenteditable="false"),
            ~s(data-leaf-raw="&lt;Hero/&gt;"),
            ~s(<video src="/v.mp4" controls),
            ~s(href="/rel"),
            ~s(href="#top"),
            ~s(href="mailto:a@b.c")
          ] do
        assert out =~ kept, "lost #{kept}"
      end

      refute out =~ "rel=", "links are not rewritten"
    end

    test "leaves text, entities and curly braces alone" do
      assert Sanitizer.html("<p>a &amp; b &lt;c&gt; {x} é 😀</p><code>{:ok}</code>") ==
               "<p>a &amp; b &lt;c&gt; {x} é 😀</p><code>{:ok}</code>"
    end
  end

  describe "the visual surface" do
    test "renders a typed <img onerror> without the handler" do
      inner = surface("<img src=x onerror=alert(1)>")
      assert inner =~ ~s(<img src="x")
      refute inner =~ "onerror"
    end

    test "renders a javascript: link without its destination" do
      inner = surface("[x](javascript:alert\\(1\\))")
      refute inner =~ "javascript:"
      assert inner =~ ">x</a>"
    end

    test "keeps a sized image in a figure" do
      inner =
        surface(
          ~s(<figure><img src="/a.png" alt="a" width="120" /><figcaption>cap</figcaption></figure>)
        )

      assert inner =~ ~s(width="120")
      assert inner =~ "<figcaption>cap</figcaption>"
    end

    test "set_content and a collaborator's operation take the same path" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          id: "s",
          mode: :visual,
          content: "",
          visual_html: "",
          deny: []
        }
      }

      attack = "<img src=x onerror=alert(1)>"

      assert {:ok, after_set} = Leaf.update(%{action: :set_content, content: attack}, socket)
      refute after_set.assigns.visual_html =~ "onerror"

      assert {:ok, after_op} =
               Leaf.update(
                 %{
                   action: :apply_operation,
                   content: attack,
                   op: %{at: 0, remove: 0, insert: attack}
                 },
                 socket
               )

      refute after_op.assigns.visual_html =~ "onerror"
    end
  end
end
