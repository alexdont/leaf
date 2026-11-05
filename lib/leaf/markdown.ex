defmodule Leaf.Markdown do
  @moduledoc false
  # Markdown to the editor's HTML: MDEx with the sanitizer, the extensions
  # Leaf adds on top (callouts, task lists, spoilers), hashtags and wiki links.

  import Leaf.PreservedTags,
    only: [escape_attr: 1, escape_text: 1, extract_preserved_tags: 2, restore_preserved_tags: 3]

  # Empty content still emits a `<p><br></p>` paragraph so the
  # contenteditable starts with the right block wrapper on first paint —
  # without it, the user can click in and start typing before the JS
  # hook's `mounted()` callback runs the same fixup, and their first
  # characters end up as bare text inside the editor div (no `<p>`).
  # That breaks the hybrid auto-format helpers (`_maybeAutoFormatHeading`
  # & co.) which require the current block to be a `<p>`.
  # 2-arity variant: when `preserve_tags` is non-empty, custom/unknown tags
  # (e.g. <Hero/>, <CTA/>) are pulled out of the markdown BEFORE MDEx
  # (which would otherwise mangle their form), rendered as atomic,
  # non-editable placeholder blocks, and restored verbatim. The client
  # serializes those placeholders straight back to their original source,
  # so custom XML round-trips byte-for-byte through visual/hybrid mode.
  @doc false
  def markdown_to_html(markdown, opts) when is_binary(markdown) and is_map(opts) do
    preserve = Map.get(opts, :preserve_tags, [])

    html =
      if preserve == [] do
        markdown_to_html(markdown)
      else
        {protected, store} = extract_preserved_tags(markdown, preserve)

        protected
        |> markdown_to_html()
        |> restore_preserved_tags(store, opts)
      end

    html = if Map.get(opts, :hashtags, false), do: decorate_hashtags(html), else: html
    if Map.get(opts, :wiki_links, false), do: decorate_wiki_links(html), else: html
  end

  def markdown_to_html(nil), do: "<p><br></p>"
  def markdown_to_html(""), do: "<p><br></p>"

  def markdown_to_html(markdown) do
    case MDEx.to_html(markdown,
           render: [hardbreaks: true, unsafe: true],
           sanitize: Leaf.Sanitizer.options()
         ) do
      {:ok, html} ->
        clean_html(html)

      {:error, _} ->
        "<p>" <> Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(markdown)) <> "</p>"
    end
  end

  # MDEx/comrak occasionally adds newlines inside inline elements; collapse
  # those so HTML mode shows clean single-line tags.
  defp clean_html(html) do
    html
    |> String.replace(~r/<(h[1-6]|p|li|blockquote|a)([^>]*)>\n/, "<\\1\\2>")
    |> String.replace(~r/\s*<\/(h[1-6]|p|li|blockquote|a)>/, "</\\1>")
    |> unwrap_loose_list_items()
    |> apply_task_lists()
    |> apply_callouts()
    |> apply_spoiler_syntax()
    |> String.trim()
  end

  # GFM callouts: `> [!NOTE]` etc. MDEx/comrak leaves `[!NOTE]` as literal text
  # at the start of the blockquote's first paragraph. Promote the blockquote
  # to a styled callout with a derived (non-editable) title label; the client
  # serializes it back to `> [!NOTE]`.
  defp apply_callouts(html) do
    Regex.replace(
      ~r/<blockquote>\s*<p>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(?:<br\s*\/?>)?\s*/i,
      html,
      fn _full, type ->
        lower = String.downcase(type)
        title = String.capitalize(lower)

        ~s(<blockquote class="leaf-callout leaf-callout-#{lower}" data-callout="#{lower}"><p class="leaf-callout-title" contenteditable="false">#{title}</p><p>)
      end
    )
  end

  # GFM task lists: MDEx/comrak leaves `[ ] text` / `[x] text` as literal text
  # inside `<li>`. Promote those to a clickable checkbox item that the
  # client serializes back to `- [ ] ` / `- [x] `.
  defp apply_task_lists(html) do
    html
    |> unwrap_loose_task_items()
    |> convert_task_checkboxes()
  end

  # A *loose* list (any blank line between items) wraps each item's content
  # in a `<p>`: `<li><p>text</p></li>`. The hybrid editor expects inline
  # content directly inside the `<li>` — a `<p>` inside traps the cursor
  # (the current block resolves to the inner `<p>`, so Enter inserts a
  # nested paragraph instead of a new list item and the bullet gets stuck).
  # Unwrap the single-paragraph case back to `<li>text</li>`. The negative
  # lookahead keeps the match to ONE paragraph so genuinely multi-block
  # items (`<li><p>a</p><p>b</p></li>`, `<li><p>a</p><ul>…</ul></li>`) are
  # left untouched. Runs before `apply_task_lists` so loose checklists are
  # unwrapped here and still get their checkbox.
  defp unwrap_loose_list_items(html) do
    Regex.replace(
      ~r/<li([^>]*)>\s*<p>((?:(?!<\/p>)[\s\S])*?)<\/p>\s*<\/li>/,
      html,
      "<li\\1>\\2</li>"
    )
  end

  # A *loose* list (any blank line between items) wraps each item's content
  # in a `<p>`: `<li><p>[ ] x</p></li>`. Unwrap task items back to
  # `<li>[ ] x</li>` so the checkbox match still fires — otherwise loose
  # checklists round-trip as literal "[ ] x" text.
  defp unwrap_loose_task_items(html) do
    Regex.replace(
      ~r/<li>\s*<p>\s*(\[[ xX]\][\s\S]*?)<\/p>\s*<\/li>/,
      html,
      "<li>\\1</li>"
    )
  end

  defp convert_task_checkboxes(html) do
    Regex.replace(~r/<li>\s*\[([ xX])\]\s?/, html, fn _full, mark ->
      checked = if mark in ["x", "X"], do: "true", else: "false"

      ~s(<li class="leaf-task" data-checked="#{checked}"><span class="leaf-task-box" contenteditable="false"></span>)
    end)
  end

  # Convert `||text||` (Discord-style spoiler) to <span class="leaf-spoiler">.
  # Skip anything inside <code>…</code> or <pre>…</pre> so literal pipes in
  # code samples stay literal.
  defp apply_spoiler_syntax(html) do
    html
    |> String.split(~r/(<(?:pre|code)\b[^>]*>.*?<\/(?:pre|code)>)/is, include_captures: true)
    |> Enum.map_join("", fn chunk ->
      if String.match?(chunk, ~r/^<(?:pre|code)\b/i) do
        chunk
      else
        String.replace(chunk, ~r/\|\|(.+?)\|\|/s, "<span class=\"leaf-spoiler\">\\1</span>")
      end
    end)
  end

  @doc false
  def sanitize_html(html, deny) when is_binary(html) and is_list(deny) do
    html
    |> maybe_strip_html_links(deny)
    |> maybe_strip_html_images(deny)
  end

  @doc false
  def sanitize_markdown(markdown, deny) when is_binary(markdown) and is_list(deny) do
    markdown
    |> maybe_strip_markdown_images(deny)
    |> maybe_strip_markdown_links(deny)
  end

  defp maybe_strip_html_links(html, deny) do
    if :links in deny do
      String.replace(html, ~r/<a\b[^>]*>(.*?)<\/a>/is, "\\1")
    else
      html
    end
  end

  defp maybe_strip_html_images(html, deny) do
    if :images in deny do
      String.replace(html, ~r/<img\b[^>]*\/?\s*>/is, "")
    else
      html
    end
  end

  defp maybe_strip_markdown_images(markdown, deny) do
    if :images in deny do
      String.replace(markdown, ~r/!\[(.*?)\]\((.*?)\)/, "")
    else
      markdown
    end
  end

  defp maybe_strip_markdown_links(markdown, deny) do
    if :links in deny do
      String.replace(markdown, ~r/(?<!!)\[(.*?)\]\((.*?)\)/, "\\1")
    else
      markdown
    end
  end

  # Wrap `#tag` occurrences in a decoration span so hashtags read as tags
  # rather than prose. Two things keep this safe:
  #
  # - `<span>` serializes back as its own text (see `convertNode`), so the
  #   markdown stays `#tag` and nothing about the round trip changes.
  # - Substitution only happens in text runs — never inside a tag, and
  #   never inside `<pre>` / `<code>` / `<a>`, where a `#` is a literal or
  #   a URL fragment rather than a tag.
  #
  # The leading-boundary group mirrors the `:word_start` suggestion
  # boundary, so `/page#section` is left alone for the same reason the
  # popup doesn't open there.
  @hashtag_re ~r/(^|[\s(\[>])#(\p{L}[\p{L}\p{N}_-]*)/u
  @hashtag_skip_re ~r{(<(?:pre|code|a)\b[^>]*>.*?</(?:pre|code|a)>)}is

  @doc false
  def decorate_hashtags(html) do
    html
    |> String.split(@hashtag_skip_re, include_captures: true)
    |> Enum.map_join("", &decorate_hashtags_chunk/1)
  end

  defp decorate_hashtags_chunk(chunk) do
    if Regex.match?(~r/^<(?:pre|code|a)\b/i, chunk) do
      chunk
    else
      chunk
      |> String.split(~r/(<[^>]*>)/, include_captures: true)
      |> Enum.map_join("", &decorate_hashtags_text/1)
    end
  end

  defp decorate_hashtags_text("<" <> _ = tag), do: tag

  defp decorate_hashtags_text(text) do
    Regex.replace(@hashtag_re, text, ~s(\\1<span class="leaf-hashtag">#\\2</span>))
  end

  # Wrap `[[Target]]` in a decoration span so wiki links read as links rather
  # than literal brackets. Deliberately a `<span>`, never an `<a>`: `convertNode`
  # serializes an unknown span as its own text, so the markdown stays `[[Target]]`
  # and the round trip is unchanged — whereas an `<a>` would serialize as
  # `[label](href)` and rewrite the document into ordinary markdown links.
  #
  # Three shapes, matching Obsidian: `[[Target]]`, `[[Target|Alias]]` and
  # `[[Target#Heading]]`. The visible text is the alias where one is given, the
  # target otherwise; the target and heading ride along as data attributes so
  # the client can ask the host to resolve them.
  #
  # Skips `<pre>`, `<code>` and `<a>` for the same reason hashtags do: inside
  # them the brackets are literal, or already part of a link.
  @wiki_link_re ~r/\[\[([^\[\]|#]+?)(?:#([^\[\]|]+?))?(?:\|([^\[\]]+?))?\]\]/
  @wiki_link_skip_re ~r{(<(?:pre|code|a)\b[^>]*>.*?</(?:pre|code|a)>)}is

  @doc false
  def decorate_wiki_links(html) do
    html
    |> String.split(@wiki_link_skip_re, include_captures: true)
    |> Enum.map_join("", &decorate_wiki_links_chunk/1)
  end

  defp decorate_wiki_links_chunk(chunk) do
    if Regex.match?(~r/^<(?:pre|code|a)\b/i, chunk) do
      chunk
    else
      chunk
      |> String.split(~r/(<[^>]*>)/, include_captures: true)
      |> Enum.map_join("", &decorate_wiki_links_text/1)
    end
  end

  defp decorate_wiki_links_text("<" <> _ = tag), do: tag

  defp decorate_wiki_links_text(text) do
    Regex.replace(@wiki_link_re, text, fn _whole, target, heading, alias_text ->
      wiki_link_span(String.trim(target), String.trim(heading), String.trim(alias_text))
    end)
  end

  defp wiki_link_span(target, heading, alias_text) do
    label = if alias_text == "", do: display_target(target, heading), else: alias_text

    # The raw source is carried verbatim so the client can rebuild the exact
    # `[[…]]` text without re-deriving it from the parts.
    raw = "[[" <> target <> heading_suffix(heading) <> alias_suffix(alias_text) <> "]]"

    ~s(<span class="leaf-wikilink" data-leaf-wikilink="#{escape_attr(target)}") <>
      heading_attr(heading) <>
      ~s( data-leaf-wikilink-raw="#{escape_attr(raw)}">) <>
      escape_text(label) <> "</span>"
  end

  defp display_target(target, ""), do: target
  defp display_target(target, heading), do: target <> " › " <> heading

  defp heading_suffix(""), do: ""
  defp heading_suffix(heading), do: "#" <> heading

  defp alias_suffix(""), do: ""
  defp alias_suffix(alias_text), do: "|" <> alias_text

  defp heading_attr(""), do: ""
  defp heading_attr(heading), do: ~s( data-leaf-wikilink-heading="#{escape_attr(heading)}")
end
