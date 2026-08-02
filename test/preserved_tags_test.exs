defmodule Leaf.PreservedTagsTest do
  @moduledoc """
  Preserved custom tags render as atomic chips whose *preview* is rich
  (attributes, thumbnail, formatted children) while the *serialized* form
  stays the verbatim source in `data-leaf-raw`.

  The split matters: the preview is what a writer reads, `data-leaf-raw` is
  what round-trips. Tests here pin both halves so a change to one can't
  quietly redefine the other.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defp visual_html(opts) do
    opts
    |> Keyword.put_new(:id, "editor-1")
    |> then(&render_component(Leaf, &1))
  end

  describe "atomic block preview" do
    test "attributes are typeset by role, not dumped as source" do
      html =
        visual_html(
          content: ~s|<Hero title="Leaf 0.5.0" subtitle="Readable atomic blocks" />|,
          preserve_tags: ["Hero"]
        )

      assert html =~ ~s|<span class="leaf-atomic-name">Hero</span>|
      assert html =~ ~s|<span class="leaf-atomic-title">Leaf 0.5.0</span>|
      assert html =~ ~s|<span class="leaf-atomic-subtitle">Readable atomic blocks</span>|
      # ...and nothing is left over to show as source. (The raw form is
      # still in `data-leaf-raw` — that is the round trip, not the preview.)
      refute html =~ "leaf-atomic-rest"
    end

    test "role synonyms are recognised" do
      html =
        visual_html(
          content: ~s|<Panel heading="Ship it" tagline="Now with less code" kicker="Release" />|,
          preserve_tags: ["Panel"]
        )

      assert html =~ ~s|<span class="leaf-atomic-eyebrow">Release</span>|
      assert html =~ ~s|<span class="leaf-atomic-title">Ship it</span>|
      assert html =~ ~s|<span class="leaf-atomic-subtitle">Now with less code</span>|
    end

    test "an attribute with no role falls through to the source line" do
      html =
        visual_html(
          content: ~s|<Hero title="Welcome" variant="wide" columns="3" />|,
          preserve_tags: ["Hero"]
        )

      assert html =~ ~s|<span class="leaf-atomic-title">Welcome</span>|
      assert html =~ "leaf-atomic-rest"
      assert html =~ "variant=&quot;wide&quot; columns=&quot;3&quot;"
    end

    # `label` names the block on its own and captions a button next to a
    # destination — the same word doing two jobs.
    test "label reads as a title alone and as a button next to a link" do
      alone = visual_html(content: ~s|<Badge label="Beta" />|, preserve_tags: ["Badge"])
      assert alone =~ ~s|<span class="leaf-atomic-title">Beta</span>|
      refute alone =~ "leaf-atomic-cta"

      with_link =
        visual_html(content: ~s|<CTA label="Sign up" href="/join" />|, preserve_tags: ["CTA"])

      assert with_link =~ ~s|<span class="leaf-atomic-cta-label">Sign up</span>|
      assert with_link =~ ~s|<span class="leaf-atomic-cta-link">/join</span>|
    end

    test "children render as formatted text, not as a hidden payload" do
      html =
        visual_html(
          content: ~s|<Header>Some **bold** and a [link](/somewhere).</Header>|,
          preserve_tags: ["Header"]
        )

      assert html =~ "leaf-atomic-body"
      assert html =~ "<strong>bold</strong>"
      # The anchor keeps its look but loses its destination — a live href
      # inside a contenteditable is still a ctrl-click / drag target.
      assert html =~ ~s|<a data-leaf-href="/somewhere">link</a>|
      refute html =~ ~s|<a href="/somewhere"|
    end

    test "an image-ish attribute renders as a banner" do
      html =
        visual_html(
          content: ~s|<Hero image="/img/hero.png" />|,
          preserve_tags: ["Hero"]
        )

      assert html =~ ~s|class="leaf-atomic-media" src="/img/hero.png"|
      # The banner is not also repeated as a leftover attribute.
      refute html =~ "leaf-atomic-rest"
    end

    test "a picture-naming attribute takes any URL at face value" do
      # Real image URLs routinely carry no extension — CDN paths, signed
      # URLs, placeholder services. Demanding one meant most real content
      # got no thumbnail at all.
      html =
        visual_html(
          content: ~s|<Hero image="https://placehold.co/200x80/png" />|,
          preserve_tags: ["Hero"]
        )

      assert html =~ ~s(src="https://placehold.co/200x80/png")
    end

    test "a non-URL attribute value does not become a banner" do
      html =
        visual_html(
          content: ~s|<Hero image="not a url" />|,
          preserve_tags: ["Hero"]
        )

      refute html =~ "leaf-atomic-media"
    end

    # `src` is ambiguous — <Audio src="…mp3"> uses it too — so unlike
    # `image`/`poster`/`cover` it has to actually look like an image.
    test "an ambiguous src only becomes a banner when it looks like an image" do
      audio =
        visual_html(content: ~s|<Audio src="/track.mp3" />|, preserve_tags: ["Audio"])

      refute audio =~ "leaf-atomic-media"

      picture =
        visual_html(content: ~s|<Figure src="/shot.jpg" />|, preserve_tags: ["Figure"])

      assert picture =~ ~s(src="/shot.jpg")
    end

    test "a tag with nothing to show collapses to its nameplate" do
      html = visual_html(content: ~s|<Divider />|, preserve_tags: ["Divider"])

      assert html =~ ~s|<span class="leaf-atomic-name">Divider</span>|
      refute html =~ "leaf-atomic-preview"
      refute html =~ "leaf-atomic-media"
    end

    # A bare `<Image>` mid-sentence is worse than useless — every one of
    # them looks identical — so the fallback chain runs down to a filename
    # before it gives up.
    test "an inline tag always carries something that identifies it" do
      for {content, expected} <- [
            {~s|x <Image src="pic.png" alt="A cat" /> y|, "A cat"},
            {~s|x <Image src="/img/pic.png" /> y|, "pic.png"},
            {~s|x <Image src="pic.png" /> y|, "pic.png"},
            {~s|x <Link href="/docs" /> y|, "/docs"}
          ] do
        html = visual_html(content: content, preserve_tags: ["Image", "Link"])
        assert html =~ ~s|<span class="leaf-atomic-value">#{expected}</span>|
      end
    end

    test "an inline tag stays the size of a word" do
      html =
        visual_html(
          content: ~s|A paragraph with <Image src="/pic.png" alt="A cat" /> inline.|,
          preserve_tags: ["Image"]
        )

      assert html =~ ~s|class="leaf-atomic leaf-atomic-inline"|
      assert html =~ ~s|<span class="leaf-atomic-name">Image</span>|
      # No banner, no rendered children, no leftover source in a chip that
      # has to sit inside a sentence.
      refute html =~ "leaf-atomic-media"
      refute html =~ "leaf-atomic-body"
      refute html =~ "leaf-atomic-rest"
    end

    test "the verbatim source survives in data-leaf-raw" do
      source = ~s|<CTA label="Sign up" href="/join">Join now</CTA>|
      html = visual_html(content: source, preserve_tags: ["CTA"])

      escaped =
        source |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s|data-leaf-raw="#{escaped}"|
    end

    test "raw HTML in children is dropped rather than injected into the preview" do
      html =
        visual_html(
          content: ~s|<Header>hi <script>alert(1)</script></Header>|,
          preserve_tags: ["Header"]
        )

      refute html =~ "<script>alert(1)</script>"
      # ...but the source is still intact for the round trip.
      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    end
  end

  describe "unpreserved-tag warning" do
    test "names the undeclared tags and how to declare them" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          visual_html(content: ~s|<Showcase a="1" /> and <Note>x</Note>|, preserve_tags: [])
        end)

      assert log =~ "<Showcase>"
      assert log =~ "<Note>"
      assert log =~ ~s|preserve_tags={["Showcase", "Note"]}|
    end

    test "stays quiet for declared tags" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          visual_html(content: ~s|<Showcase a="1" />|, preserve_tags: ["Showcase"])
        end)

      refute log =~ "Showcase"
    end

    test "stays quiet for tags inside code" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          visual_html(content: "Use `<Showcase />` like this.", preserve_tags: [])
        end)

      refute log =~ "Showcase"
    end

    test "can be switched off" do
      Application.put_env(:leaf, :warn_unpreserved_tags, false)
      on_exit(fn -> Application.delete_env(:leaf, :warn_unpreserved_tags) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          visual_html(content: ~s|<Showcase />|, preserve_tags: [])
        end)

      refute log =~ "Showcase"
    end
  end
end
