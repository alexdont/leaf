defmodule Leaf.Issues5To8Test do
  @moduledoc """
  Server side of GitHub issues #6, #7 and #8.

  - #8: a keystroke must not re-render the component. The template draws the
    document from `rendered_markdown` / `rendered_html`, which only the host
    changes (`set_content`); `content_changed` updates the live `content` /
    `visual_html` alone. Re-rendering on every keystroke made LiveView patch
    the whole component and reset the toolbar's overflow state — the toolbar
    wrapped to two lines and back as you typed.
  - #7: a mention chip carries its token's type and id.
  - #6: a suggestion result may carry an avatar.
  """
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            id: "editor-1",
            mode: :visual,
            content: "# hi",
            visual_html: "<h1>hi</h1>",
            rendered_markdown: "# hi",
            rendered_html: "<h1>hi</h1>",
            deny: []
          },
          assigns
        )
    }
  end

  describe "#8: a keystroke does not change what the template renders" do
    test "content_changed updates the live content and nothing rendered" do
      {:noreply, s} =
        Leaf.handle_event(
          "content_changed",
          %{"markdown" => "# hi there", "html" => "<h1>hi there</h1>"},
          socket()
        )

      assert s.assigns.content == "# hi there"
      assert s.assigns.visual_html == "<h1>hi there</h1>"
      assert s.assigns.rendered_markdown == "# hi"
      assert s.assigns.rendered_html == "<h1>hi</h1>"
      refute Map.has_key?(s.assigns.__changed__, :rendered_markdown)
      refute Map.has_key?(s.assigns.__changed__, :rendered_html)
    end

    test "the host replacing the content does re-render it" do
      {:ok, s} = Leaf.update(%{action: :set_content, content: "## new"}, socket())
      assert s.assigns.rendered_markdown == "## new"
      assert s.assigns.rendered_html =~ "new"
    end

    test "the template draws from the rendered copies" do
      src = File.read!(Path.expand("../lib/leaf.ex", __DIR__))
      refute src =~ "raw(@visual_html)"
      refute src =~ "><%= @content %></textarea>"
      refute src =~ "><%= @visual_html %></textarea>"
      assert src =~ "raw(@rendered_html)"
    end
  end

  describe "#7: mention chips carry type and id" do
    test "the server's render puts both on the chip" do
      uuid = "0190aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee"

      html =
        Leaf.Markdown.decorate_mentions("<p>Hi @[user:#{uuid}|Ada] and #[project:#{uuid}|Q3]</p>")

      assert html =~ ~s(data-leaf-mention-type="user" data-leaf-mention-id="#{uuid}">@Ada</span>)

      assert html =~
               ~s(data-leaf-mention-type="project" data-leaf-mention-id="#{uuid}">#Q3</span>)

      assert html =~ ~s(data-leaf-mention-raw="@[user:#{uuid}|Ada]")
    end
  end

  describe "#6: suggestion results may carry an avatar" do
    defp reply(results) do
      {:ok, s} =
        Leaf.update(
          %{action: :suggestions, trigger: "@", query: "a", seq: 1, results: results},
          socket()
        )

      [["leaf-suggestions:editor-1", payload]] = s.private.live_temp.push_events
      payload.results
    end

    test "a URL, initials, or both; a bare string is a URL" do
      [a, b, c] =
        reply([
          %{value: "1", label: "Anna", avatar: %{url: "/a.jpg"}},
          %{"value" => "2", "label" => "Bo", "avatar" => %{"initials" => "BOBBY"}},
          %{value: "3", label: "Cy", avatar: "https://x.test/c.png"}
        ])

      assert a.avatar == %{url: "/a.jpg", initials: ""}
      assert b.avatar == %{url: "", initials: "BOB"}, "initials are cut to three"
      assert c.avatar == %{url: "https://x.test/c.png", initials: ""}
    end

    test "results without one keep their shape; junk is dropped" do
      [plain, junk, empty] =
        reply([
          %{value: "1", label: "A"},
          %{value: "2", label: "B", avatar: %{url: 42, initials: :x}},
          %{value: "3", label: "C", avatar: ""}
        ])

      refute Map.has_key?(plain, :avatar)
      refute Map.has_key?(junk, :avatar)
      refute Map.has_key?(empty, :avatar)
    end
  end
end
