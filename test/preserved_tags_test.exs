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
    # The inline stylesheet names every class the chips use; assertions are
    # about the markup, so it is left out.
    |> String.replace(~r|<style.*?</style>|s, "")
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

  describe "tags inside tags" do
    @gallery ~s|<Gallery height="520">\n<Image file_uuid="aaa" alt="One"/>\n<Image file_uuid="bbb" alt="Two"/>\n</Gallery>|
    @tags ["Image", "Gallery"]

    test "the outer tag is the chip, and carries the whole source" do
      html = visual_html(content: @gallery, preserve_tags: @tags)

      assert html =~ ~s|data-leaf-tag="Gallery"|
      # One chip: the images are part of the Gallery's source, not chips of
      # their own beside it (the Gallery used to vanish into the markdown
      # parser because its images were swapped out first).
      assert length(Regex.scan(~r/ data-leaf-tag="/, html)) == 1
      assert html =~ "&lt;Image file_uuid=&quot;aaa&quot;"
      assert html =~ "&lt;/Gallery&gt;"
    end

    test "nested tags show as chiplets when the host names no picture" do
      html = visual_html(content: @gallery, preserve_tags: @tags)

      assert html =~ ~s|<span class="leaf-atomic-chiplet">Image One</span>|
      assert html =~ ~s|<span class="leaf-atomic-chiplet">Image Two</span>|
    end

    test "the host's media_url draws them as thumbnails" do
      media_url = fn "Image", %{"file_uuid" => uuid} -> "/file/#{uuid}/thumb" end

      html = visual_html(content: @gallery, preserve_tags: @tags, media_url: media_url)

      assert html =~ ~s|<img class="leaf-atomic-thumb" src="/file/aaa/thumb"|
      assert html =~ ~s|<img class="leaf-atomic-thumb" src="/file/bbb/thumb"|
      refute html =~ "leaf-atomic-chiplet"
    end

    test "two galleries in one document stay two chips" do
      html =
        visual_html(content: @gallery <> "\n\ntext\n\n" <> @gallery, preserve_tags: @tags)

      assert length(Regex.scan(~r/data-leaf-tag="Gallery"/, html)) == 2
    end
  end

  describe "media_url" do
    test "a top-level tag gets its picture as the banner" do
      media_url = fn "Image", %{"file_uuid" => uuid} -> "/file/#{uuid}/large" end

      html =
        visual_html(
          content: ~s|<Image file_uuid="abc" alt="A cat"/>|,
          preserve_tags: ["Image"],
          media_url: media_url
        )

      assert html =~ ~s|<img class="leaf-atomic-media" src="/file/abc/large"|
      assert html =~ "leaf-atomic-has-media"
    end

    test "it is told the tag, so a non-picture file is the host's call" do
      media_url = fn
        "Image", %{"file_uuid" => uuid} -> "/file/#{uuid}"
        _tag, _attrs -> nil
      end

      html =
        visual_html(
          content: ~s|<Audio file_uuid="abc" title="Episode"/>|,
          preserve_tags: ["Audio"],
          media_url: media_url
        )

      refute html =~ "<img"
      assert html =~ "Episode"
    end

    test "a picture the tag carries itself wins" do
      html =
        visual_html(
          content: ~s|<Hero image="https://x.test/a.png" file_uuid="abc"/>|,
          preserve_tags: ["Hero"],
          media_url: fn _, _ -> "/should-not-be-used" end
        )

      assert html =~ ~s|src="https://x.test/a.png"|
      refute html =~ "should-not-be-used"
    end

    test "a function that raises, or answers a non-URL, draws nothing" do
      for fun <- [
            fn _, _ -> raise "boom" end,
            fn _, _ -> "javascript:alert(1)" end,
            fn _, _ -> 42 end
          ] do
        html =
          visual_html(
            content: ~s|<Image file_uuid="abc"/>|,
            preserve_tags: ["Image"],
            media_url: fun
          )

        refute html =~ "<img"
        assert html =~ ~s|data-leaf-tag="Image"|
      end
    end
  end

  describe "block children" do
    test "a heading and a paragraph in the body stay inside the chip" do
      source = "<Showcase side=\"left\">\n### Heading\n\nWords beside the picture.\n</Showcase>"
      html = visual_html(content: source, preserve_tags: ["Showcase"])

      [chip] =
        Regex.run(
          ~r|<span class="leaf-atomic leaf-atomic-block".*?</p>|s,
          html
        )

      # Block elements in a chip's body close the <p> it lives in, which
      # threw the nameplate and attributes out below the box.
      refute chip =~ ~r|<h3|
      refute chip =~ ~r|<p>[^<]*Words|
      assert chip =~ ~s|<strong class="leaf-atomic-h">Heading</strong>|
      assert chip =~ "Words beside the picture."
      assert chip =~ ~s|<span class="leaf-atomic-rest">side=|
    end

    test "paragraphs between headings do not end the chip early" do
      source = "<Showcase side=\"left\">\n### A\n\ntext a\n\n### B\n\ntext b\n</Showcase>"
      html = visual_html(content: source, preserve_tags: ["Showcase"])

      [chip] = Regex.run(~r|<span class="leaf-atomic leaf-atomic-block".*?</p>|s, html)

      assert chip =~ "text a"
      assert chip =~ "text b"
      assert chip =~ ~s|<span class="leaf-atomic-rest">side=|
    end

    test "a list in the body is flattened too" do
      html =
        visual_html(
          content: "<Card>\n- one\n- two\n</Card>",
          preserve_tags: ["Card"]
        )

      [chip] =
        Regex.run(~r|<span class="leaf-atomic leaf-atomic-block".*?</span></span></p>|s, html)

      refute chip =~ "<ul"
      refute chip =~ "<li"
      assert html =~ ~s|<span class="leaf-atomic-li">one</span>|
      assert html =~ ~s|<span class="leaf-atomic-li">two</span>|
    end
  end

  describe "inserting a tag from the host" do
    defp insert(text, assigns) do
      socket = %Phoenix.LiveView.Socket{
        assigns: Map.merge(%{__changed__: %{}, id: "ed", preserve_tags: []}, Map.new(assigns))
      }

      {:ok, socket} = Leaf.update(%{action: :insert_markdown, text: text}, socket)
      [["leaf-command:ed", payload]] = socket.private.live_temp.push_events
      payload
    end

    test "a lone preserved tag arrives as the finished chip" do
      payload =
        insert("\n<Image file_uuid=\"abc\" alt=\"A cat\"/>\n",
          preserve_tags: ["Image"],
          media_url: fn "Image", %{"file_uuid" => u} -> "/file/#{u}/t" end
        )

      assert payload.action == "insert_markdown"
      assert payload.chip =~ ~s|src="/file/abc/t"|
      assert payload.chip =~ ~s|data-leaf-tag="Image"|
    end

    test "a whole gallery arrives as one chip with its thumbnails" do
      payload =
        insert("\n<Gallery>\n<Image file_uuid=\"a\"/>\n<Image file_uuid=\"b\"/>\n</Gallery>\n",
          preserve_tags: ["Image", "Gallery"],
          media_url: fn _, %{"file_uuid" => u} -> "/file/#{u}/t" end
        )

      assert length(Regex.scan(~r/leaf-atomic-thumb/, payload.chip)) == 2
      assert length(Regex.scan(~r/data-leaf-tag=/, payload.chip)) == 1
    end

    test "plain text, or text around a tag, is left to the browser" do
      assert insert("just words", preserve_tags: ["Image"]) |> Map.has_key?(:chip) == false

      refute insert("words <Image file_uuid=\"a\"/> more", preserve_tags: ["Image"])
             |> Map.has_key?(:chip)
    end

    test "with nothing preserved there is no chip" do
      refute insert("<Image file_uuid=\"a\"/>", preserve_tags: []) |> Map.has_key?(:chip)
    end
  end

  describe "tag_previews kinds" do
    @previews %{
      "Headline" => :headline,
      "Showcase" => :split,
      "CTA" => :button,
      "Embed" => :frame,
      "Audio" => :audio
    }

    defp kinds(source, tags, extra \\ []) do
      visual_html([content: source, preserve_tags: tags, tag_previews: @previews] ++ extra)
    end

    test "a headline is its text, set large, with no attribute line" do
      html = kinds(~s|<Headline stretch="30">Big words</Headline>|, ["Headline"])

      assert html =~ "leaf-atomic-kind-headline"
      assert html =~ ~s|<span class="leaf-kind-headline">Big words</span>|
      refute html =~ "leaf-atomic-rest"
    end

    test "a showcase puts the picture beside the text, on its side" do
      source =
        "<Showcase file_uuid=\"u1\" side=\"right\" height=\"medium\">\n### Hi\n\nBody\n</Showcase>"

      html =
        kinds(source, ["Showcase"],
          media_url: fn "Showcase", %{"file_uuid" => u} -> "/file/#{u}" end
        )

      assert html =~ "leaf-kind-split-right"
      assert html =~ ~s|<img class="leaf-kind-picture" src="/file/u1"|
      assert html =~ ~s|<strong class="leaf-atomic-h">Hi</strong>|
      assert html =~ "height medium"
    end

    test "a showcase with no picture says so, and defaults to the left" do
      html = kinds(~s|<Showcase src="">Words</Showcase>|, ["Showcase"])

      assert html =~ "leaf-kind-split-left"
      assert html =~ ~s|<span class="leaf-kind-placeholder">Picture</span>|
      refute html =~ "<img class=\"leaf-kind-picture\""
    end

    test "a CTA is a button, with where it goes" do
      html = kinds(~s|<CTA href="/signup">Join us</CTA>|, ["CTA"])

      assert html =~ ~s|<span class="leaf-kind-button">Join us</span>|
      assert html =~ "→ /signup"
    end

    test "an embed shows its title, address and height" do
      html = kinds(~s|<Embed src="https://x.test/demo" height="320" title="Demo" />|, ["Embed"])

      assert html =~ ~s|<span class="leaf-kind-frame-title">Demo</span>|
      assert html =~ "https://x.test/demo"
      assert html =~ "height 320"
    end

    test "an embed with no address says so" do
      html = kinds(~s|<Embed src="" height="480" title="Try it" />|, ["Embed"])

      assert html =~ "No address yet"
    end

    test "audio is a player bar with its title" do
      html = kinds(~s|<Audio file_uuid="a" title="Episode"/>|, ["Audio"])

      assert html =~ "leaf-kind-audio-play"
      assert html =~ ~s|<span class="leaf-kind-audio-title">Episode</span>|
    end

    test "a tag with no kind, or an unknown one, keeps the generic box" do
      html =
        visual_html(
          content: ~s|<Hero title="Hi"/>|,
          preserve_tags: ["Hero"],
          tag_previews: %{"Hero" => :nonsense, "Other" => :button}
        )

      assert html =~ "leaf-atomic-title"
      refute html =~ "leaf-atomic-kind-"
    end

    test "kind names are matched without regard to case, and may be strings" do
      html =
        visual_html(
          content: ~s|<CTA>Go</CTA>|,
          preserve_tags: ["CTA"],
          tag_previews: %{"cta" => "button"}
        )

      assert html =~ "leaf-kind-button"
    end

    test "an inline tag stays a word even with a kind" do
      html = kinds("Press <CTA>Go</CTA> now", ["CTA"])

      assert html =~ "leaf-atomic-inline"
      refute html =~ "leaf-kind-button"
    end

    test "the user's text is escaped in every kind" do
      html = kinds(~s|<Embed src="x" title="Tom & Jerry <i" />|, ["Embed"])

      [chip] = Regex.run(~r|<span class="leaf-atomic leaf-atomic-block.*?</p>|s, html)

      assert chip =~ "Tom &amp; Jerry"
      refute String.replace(chip, ~r/data-leaf-raw="[^"]*"/, "") =~ "Jerry <"
    end

    test "an inserted tag arrives drawn as its kind" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          id: "ed",
          preserve_tags: ["Headline"],
          tag_previews: %{"Headline" => :headline}
        }
      }

      {:ok, socket} =
        Leaf.update(
          %{
            action: :insert_markdown,
            text: ~s|\n<Headline stretch="30">Headline text</Headline>\n|
          },
          socket
        )

      [["leaf-command:ed", payload]] = socket.private.live_temp.push_events
      assert payload.chip =~ ~s|<span class="leaf-kind-headline">Headline text</span>|
    end
  end

  describe "preview stylesheet" do
    test "ships with the markup, not only with the JS bundle" do
      raw =
        render_component(Leaf,
          id: "e",
          content: ~s|<CTA>Go</CTA>|,
          preserve_tags: ["CTA"],
          tag_previews: %{"CTA" => :button}
        )

      [style] = Regex.run(~r|<style.*?</style>|s, raw)

      for selector <- [
            ".leaf-kind-button",
            ".leaf-kind-split",
            ".leaf-kind-headline",
            ".leaf-kind-frame",
            ".leaf-kind-audio",
            ".leaf-atomic-thumb",
            ".leaf-atomic-h"
          ] do
        assert style =~ selector
      end
    end
  end
end
