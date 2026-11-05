defmodule Leaf.PreservedTags do
  @moduledoc false
  # Preserved custom tags (`<Hero/>`): pulling them out of the markdown
  # before MDEx sees it, putting them back, and drawing them as chips.

  import Leaf.Translate, only: [t: 1]

  # Replace each OUTERMOST occurrence of a preserved tag with an inert text
  # token, returning {protected_markdown, %{token => original_source}}.
  #
  # Outermost matters: `<Gallery><Image …/></Gallery>` has two preserved
  # tags in it, and the inner one used to be replaced first, which left the
  # outer match without its source to find — the Gallery's own tags were
  # then handed to the markdown parser, which swallowed them. A tag inside
  # another is part of that tag's source and travels with it.
  # Attributes up to the tag's own `>`: a quoted value may hold one
  # (`title="a > b"`), and stopping at it dropped the tag.
  @tag_attrs ~S{(?:[^>"']|"[^"]*"|'[^']*')*?}

  @doc false
  def extract_preserved_tags(markdown, preserve_tags) do
    # A tag inside a code span or fence is a sample, not a component.
    code_ranges =
      ~r/```.*?```|`[^`\n]*`/s
      |> Regex.scan(markdown, return: :index)
      |> Enum.map(&hd/1)

    ranges =
      preserve_tags
      |> Enum.flat_map(fn tag ->
        t = Regex.escape(to_string(tag))

        {:ok, re} =
          Regex.compile("<#{t}\\b#{@tag_attrs}/>|<#{t}\\b#{@tag_attrs}>.*?</#{t}>", "is")

        re
        |> Regex.scan(markdown, return: :index)
        |> Enum.map(fn [range | _] -> balance_range(markdown, t, range) end)
      end)
      |> Enum.reject(fn {start, _len} ->
        Enum.any?(code_ranges, fn {cs, cl} -> start >= cs and start < cs + cl end)
      end)
      |> Enum.sort_by(fn {start, len} -> {start, -len} end)
      |> outermost_ranges()

    {protected, store, _i} =
      ranges
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce({markdown, %{}, 0}, fn {{start, len}, i}, {md, store, _} ->
        token = "LEAFPRESERVED#{i}LEAFEND"
        raw = binary_part(md, start, len)
        before = binary_part(md, 0, start)
        rest = binary_part(md, start + len, byte_size(md) - start - len)
        {before <> token <> rest, Map.put(store, token, raw), i}
      end)

    {protected, store}
  end

  # A tag inside a tag of the same name (`<Note><Note>x</Note></Note>`): the
  # lazy match ends at the inner close. Walk the opens and closes from the
  # start and stop where the depth returns to zero.
  defp balance_range(markdown, t, {start, len} = range) do
    {:ok, re} = Regex.compile("<#{t}\\b|</#{t}\\s*>", "i")
    rest = binary_part(markdown, start, byte_size(markdown) - start)

    re
    |> Regex.scan(rest, return: :index)
    |> Enum.map(&hd/1)
    |> Enum.reduce_while(0, fn {at, l}, depth ->
      closing? = binary_part(rest, at, 2) == "</"
      depth = if closing?, do: depth - 1, else: depth + 1
      if depth == 0, do: {:halt, {:done, at + l}}, else: {:cont, depth}
    end)
    |> case do
      {:done, stop} when stop > len -> {start, stop}
      _ -> range
    end
  end

  # Ranges sorted by start (longest first on a tie), keeping those that do
  # not begin inside one already kept.
  defp outermost_ranges(ranges) do
    {kept, _end} =
      Enum.reduce(ranges, {[], 0}, fn {start, len}, {acc, last_end} ->
        if start >= last_end, do: {[{start, len} | acc], start + len}, else: {acc, last_end}
      end)

    Enum.reverse(kept)
  end

  # Swap tokens back for atomic placeholder spans carrying the verbatim
  # source in a `data-leaf-raw` attribute. A standalone token that MDEx
  # wrapped in its own `<p>` becomes the taller block chip; an inline token
  # stays a compact inline one.
  @doc false
  def restore_preserved_tags(html, store, opts) do
    Enum.reduce(store, html, fn {token, raw}, acc ->
      acc
      |> String.replace("<p>#{token}</p>", "<p>#{preserved_chip(raw, :block, opts)}</p>")
      |> String.replace(token, preserved_chip(raw, :inline, opts))
    end)
  end

  # Render one preserved custom tag as an atomic block.
  #
  # The block is `contenteditable="false"` and carries the verbatim source
  # in `data-leaf-raw` — that attribute, not the rendered preview, is what
  # the client serializes back, so everything below is free to be as rich
  # as it likes without any risk to the round trip.
  #
  # What it renders is a *preview of the component*, not its source. A
  # writer scanning their own document needs to know which component this
  # is and roughly what it will say; `title="…" subtitle="…"` in monospace
  # answers neither question without being read like code. So known
  # attribute names are mapped to typographic roles — title, subtitle,
  # eyebrow, media, call-to-action — and typeset in the editor's own prose
  # voice. Only the attributes with no role left over are shown as source,
  # small and faint, because for those there is nothing better to say.
  #
  # The scale is deliberately restrained: this is a placeholder that reads
  # like prose, not an imitation of the published component. A document
  # with four Heroes still has to be readable, and Leaf has no idea what
  # the host's Hero actually looks like.
  #
  # Every child element is phrasing content, because the block form still
  # sits inside the `<p>` MDEx produced.
  @doc false
  def preserved_chip(raw, layout, opts) do
    {name, attrs, inner} = parse_preserved_tag(raw)
    roles = attribute_roles(attrs)
    roles = with_host_media(roles, name, attrs, opts)

    kind = if layout == :block, do: tag_kind(opts, name), else: nil

    body =
      case {layout, kind} do
        {:inline, _} -> inline_chip_body(name, roles, inner)
        {:block, nil} -> block_chip_body(name, roles, inner, opts)
        {:block, kind} -> kind_chip_body(kind, name, attrs, roles, inner, opts)
      end

    # `has-media` lets the stylesheet know the nameplate is sitting over a
    # banner rather than over the first line of text, so only the text case
    # needs to reserve room for it.
    classes =
      case layout do
        :inline -> "leaf-atomic leaf-atomic-inline"
        :block when kind != nil -> "leaf-atomic leaf-atomic-block leaf-atomic-kind-#{kind}"
        :block when roles.media != "" -> "leaf-atomic leaf-atomic-block leaf-atomic-has-media"
        :block -> "leaf-atomic leaf-atomic-block"
      end

    ~s(<span class="#{classes}" contenteditable="false" data-leaf-raw="#{escape_attr(raw)}") <>
      ~s( data-leaf-tag="#{escape_attr(name)}" title="#{escape_attr(preserved_tooltip(raw))}">) <>
      body <> ~s(</span>)
  end

  @tag_kinds ~w(headline split button frame audio)a

  @doc false
  def normalize_tag_previews(map) when is_map(map) do
    for {tag, kind} <- map,
        kind = normalize_kind(kind),
        into: %{},
        do: {String.downcase(to_string(tag)), kind}
  end

  def normalize_tag_previews(_), do: %{}

  defp normalize_kind(kind) when kind in @tag_kinds, do: kind

  defp normalize_kind(kind) when is_binary(kind) do
    Enum.find(@tag_kinds, &(Atom.to_string(&1) == kind))
  end

  defp normalize_kind(_), do: nil

  defp tag_kind(%{tag_previews: previews}, name) when is_map(previews),
    do: Map.get(previews, String.downcase(name))

  defp tag_kind(_opts, _name), do: nil

  # A kind's body. Same nameplate and edit hint as the generic box, so the
  # block still reads as one thing you can double-click; what differs is the
  # preview, drawn like the component it stands for. Everything is phrasing
  # content (spans) because the chip lives inside a `<p>`; the stylesheet
  # does the block layout.
  defp kind_chip_body(kind, name, attrs, roles, inner, opts) do
    nameplate = ~s(<span class="leaf-atomic-name">#{escape_text(name)}</span>)
    hint = ~s(<span class="leaf-atomic-hint">#{escape_text(t("Double-click to edit"))}</span>)

    nameplate <> hint <> kind_preview(kind, attrs, roles, inner, opts)
  end

  defp kind_preview(:headline, attrs, roles, inner, _opts) do
    text = first_present([render_body(inner), escape_text(roles.title)], t("Headline text"))
    stretch = attr_value(attrs, "stretch")

    ~s(<span class="leaf-kind-headline">#{text}</span>) <>
      if(stretch == "",
        do: "",
        else:
          ~s(<span class="leaf-kind-meta">#{escape_text(t("stretch"))} #{escape_text(stretch)}</span>)
      )
  end

  defp kind_preview(:split, attrs, roles, inner, _opts) do
    side = if String.downcase(attr_value(attrs, "side")) == "right", do: "right", else: "left"
    {children, inner} = nested_tags(inner, %{})
    body = first_present([render_body(inner)], "")

    picture =
      case roles.media do
        "" ->
          ~s(<span class="leaf-kind-placeholder">#{escape_text(t("Picture"))}</span>)

        url ->
          ~s(<img class="leaf-kind-picture" src="#{escape_attr(url)}" alt="#{escape_attr(attr_value(attrs, "alt"))}" loading="lazy">)
      end

    meta =
      attrs
      |> Enum.reject(fn {k, v} ->
        String.downcase(k) in ~w(src file_uuid side alt image) or String.trim(v) == ""
      end)
      |> Enum.map_join(" · ", fn {k, v} -> "#{k} #{truncate(v, 24)}" end)

    ~s(<span class="leaf-kind-split leaf-kind-split-#{side}">) <>
      ~s(<span class="leaf-kind-split-media">#{picture}</span>) <>
      ~s(<span class="leaf-kind-split-text">#{body}#{children}</span></span>) <>
      if(meta == "", do: "", else: ~s(<span class="leaf-kind-meta">#{escape_text(meta)}</span>))
  end

  defp kind_preview(:button, attrs, roles, inner, _opts) do
    label =
      first_present(
        [render_body(inner), escape_text(roles.cta_label), escape_text(roles.title)],
        t("Button")
      )

    link = first_present([roles.link, attr_value(attrs, "href")], "")

    ~s(<span class="leaf-kind-button">#{label}</span>) <>
      if(link == "",
        do: "",
        else: ~s(<span class="leaf-kind-meta">→ #{escape_text(truncate(link, 60))}</span>)
      )
  end

  defp kind_preview(:frame, attrs, roles, _inner, _opts) do
    src = first_present([attr_value(attrs, "src"), roles.link], "")
    height = attr_value(attrs, "height")
    title = first_present([escape_text(roles.title)], t("Embedded page"))

    ~s(<span class="leaf-kind-frame">) <>
      ~s(<span class="leaf-kind-frame-title">#{title}</span>) <>
      ~s(<span class="leaf-kind-frame-url">#{if src == "", do: escape_text(t("No address yet")), else: escape_text(truncate(src, 70))}</span>) <>
      if(height == "",
        do: "",
        else:
          ~s(<span class="leaf-kind-meta">#{escape_text(t("height"))} #{escape_text(height)}</span>)
      ) <> ~s(</span>)
  end

  defp kind_preview(:audio, attrs, roles, _inner, _opts) do
    title =
      first_present(
        [escape_text(roles.title), escape_text(file_label(attr_value(attrs, "src")))],
        t("Audio")
      )

    ~s(<span class="leaf-kind-audio"><span class="leaf-kind-audio-play">▶</span>) <>
      ~s(<span class="leaf-kind-audio-bar"></span>) <>
      ~s(<span class="leaf-kind-audio-title">#{title}</span></span>)
  end

  # The tag's body as already-escaped, inline-safe HTML; "" when empty.
  defp render_body(inner) do
    case String.trim(inner) do
      "" -> ""
      trimmed -> render_inner_markdown(trimmed)
    end
  end

  defp attr_value(attrs, key) do
    Enum.find_value(attrs, "", fn {k, v} ->
      if String.downcase(k) == key and String.trim(v) != "", do: String.trim(v)
    end)
  end

  defp first_present(values, default) do
    Enum.find(values, default, &(&1 not in ["", nil]))
  end

  # The host's answer to "which picture is this tag?" (`:media_url`), used
  # only when the tag carries no picture of its own that Leaf can draw.
  defp with_host_media(%{media: ""} = roles, name, attrs, opts) do
    case host_media_url(opts, name, attrs) do
      "" -> roles
      url -> %{roles | media: url}
    end
  end

  defp with_host_media(roles, _name, _attrs, _opts), do: roles

  defp host_media_url(%{media_url: fun}, name, attrs) when is_function(fun, 2) do
    case fun.(name, Map.new(attrs)) do
      url when is_binary(url) -> if url_ref?(url), do: url, else: ""
      _ -> ""
    end
  rescue
    _ -> ""
  catch
    _, _ -> ""
  end

  defp host_media_url(_opts, _name, _attrs), do: ""

  # The nameplate sits in the top-RIGHT corner, which is the one structural
  # choice here worth defending: it hands the primary reading position —
  # top-left, where the eye lands — to the writer's own content, and puts
  # the machine fact where it can be found but not tripped over.
  defp block_chip_body(name, roles, inner, opts) do
    {children, inner} = nested_tags(inner, opts)

    preview =
      [
        role_span(roles.eyebrow, "leaf-atomic-eyebrow"),
        role_span(roles.title, "leaf-atomic-title"),
        role_span(roles.subtitle, "leaf-atomic-subtitle"),
        preserved_inner_preview(inner),
        children,
        chip_cta(roles),
        chip_rest_attrs(roles.rest)
      ]
      |> Enum.reject(&(&1 == ""))

    nameplate = ~s(<span class="leaf-atomic-name">#{escape_text(name)}</span>)
    hint = ~s(<span class="leaf-atomic-hint">#{escape_text(t("Double-click to edit"))}</span>)
    media = chip_media(roles.media)

    # A tag with nothing to show (`<Divider />`) collapses to the nameplate
    # rather than opening an empty box.
    content =
      if preview == [] and media == "" do
        ""
      else
        media <> ~s(<span class="leaf-atomic-preview">#{Enum.join(preview)}</span>)
      end

    nameplate <> hint <> content
  end

  # Tags nested inside a tag's body (`<Gallery><Image …/><Image …/></Gallery>`)
  # are not markdown, so the body's markdown pass would drop them and the
  # container would look empty. They are pulled out and drawn as a row:
  # a thumbnail where the host can name a picture, else a small labelled
  # chiplet. Returns {row_html, body_without_them}.
  @nested_tag_re ~r{<([A-Z][\w.-]*)\b([^>]*?)/>|<([A-Z][\w.-]*)\b([^>]*?)>(.*?)</\3>}s

  defp nested_tags(inner, opts) do
    found = Regex.scan(@nested_tag_re, inner)

    items =
      Enum.map(found, fn
        [_whole, name, attr_src] -> nested_item(name, attr_src, opts)
        [_whole, "", "", name, attr_src, _body] -> nested_item(name, attr_src, opts)
        [_whole, name, attr_src | _] -> nested_item(name, attr_src, opts)
      end)

    row =
      if items == [],
        do: "",
        else: ~s(<span class="leaf-atomic-children">#{Enum.join(items)}</span>)

    {row, Regex.replace(@nested_tag_re, inner, "")}
  end

  defp nested_item(name, attr_src, opts) do
    attrs = parse_attr_source(attr_src)
    roles = attribute_roles(attrs) |> with_host_media(name, attrs, opts)
    label = [roles.title, roles.subtitle, file_label(roles.source)] |> Enum.find("", &(&1 != ""))

    if roles.media != "" do
      ~s(<img class="leaf-atomic-thumb" src="#{escape_attr(roles.media)}" alt="#{escape_attr(label)}" title="#{escape_attr(label)}" loading="lazy">)
    else
      ~s(<span class="leaf-atomic-chiplet">#{escape_text(name)}#{if label != "", do: " " <> escape_text(truncate(label, 24)), else: ""}</span>)
    end
  end

  # Inline tags interrupt a sentence, so they stay the size of a word: the
  # tag name plus whichever single value best identifies *which* one it is.
  # A bare `<Image>` in the middle of a paragraph is worse than useless —
  # every one of them looks the same — so the fallback chain runs all the
  # way down to a filename before it gives up.
  defp inline_chip_body(name, roles, inner) do
    value =
      [
        roles.title,
        roles.subtitle,
        roles.cta_label,
        String.trim(inner),
        file_label(roles.media),
        file_label(roles.source),
        roles.link
      ]
      |> Enum.find("", &(&1 not in ["", nil]))
      |> truncate(40)

    ~s(<span class="leaf-atomic-name">#{escape_text(name)}</span>) <>
      if value == "",
        do: "",
        else: ~s(<span class="leaf-atomic-value">#{escape_text(value)}</span>)
  end

  defp role_span("", _class), do: ""

  defp role_span(value, class) do
    ~s(<span class="#{class}">#{escape_text(truncate(value, 240))}</span>)
  end

  defp chip_media(""), do: ""

  defp chip_media(url) do
    ~s(<img class="leaf-atomic-media" src="#{escape_attr(url)}" alt="" loading="lazy">)
  end

  # A label with a destination is a button on the published page, so it
  # previews as one. The destination rides along, muted — knowing where a
  # CTA points is usually the thing you came to check.
  defp chip_cta(%{cta_label: "", link: ""}), do: ""

  defp chip_cta(%{cta_label: label, link: link}) do
    text = if label == "", do: link, else: label

    ~s(<span class="leaf-atomic-cta"><span class="leaf-atomic-cta-label">) <>
      escape_text(truncate(text, 60)) <>
      ~s(</span>) <>
      if(link == "" or label == "",
        do: "",
        else: ~s(<span class="leaf-atomic-cta-link">#{escape_text(truncate(link, 60))}</span>)
      ) <>
      ~s(</span>)
  end

  defp chip_rest_attrs([]), do: ""

  defp chip_rest_attrs(attrs) do
    text =
      attrs
      |> Enum.take(6)
      |> Enum.map_join(" ", fn {k, v} -> ~s(#{k}="#{truncate(v, 32)}") end)

    ~s(<span class="leaf-atomic-rest">#{escape_text(text)}</span>)
  end

  @preserved_attr_re ~r/([A-Za-z_:][\w.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/

  defp parse_attr_source(source) do
    @preserved_attr_re
    |> Regex.scan(source)
    |> Enum.map(fn
      [_, key, dq, "", ""] -> {key, dq}
      [_, key, "", sq, ""] -> {key, sq}
      [_, key, "", "", bare] -> {key, bare}
      [_, key | rest] -> {key, Enum.find(rest, "", &(&1 != ""))}
    end)
  end

  # {tag_name, [{attr, value}], inner_source}. Only the OPENING tag is
  # scanned for attributes — attributes on nested tags belong to those.
  defp parse_preserved_tag(raw) do
    name =
      case Regex.run(~r/<\s*([A-Za-z][\w.-]*)/, raw) do
        [_, n] -> n
        _ -> "block"
      end

    open_tag =
      case Regex.run(~r/^\s*<(?:[^>"']|"[^"]*"|'[^']*')*>/s, raw) do
        [tag] -> tag
        _ -> raw
      end

    attrs = parse_attr_source(open_tag)

    inner =
      case Regex.run(
             ~r/^\s*<(?:[^>"']|"[^"]*"|'[^']*')*(?<!\/)>(.*)<\/[A-Za-z][\w.-]*\s*>\s*$/s,
             raw
           ) do
        [_, body] -> body
        _ -> ""
      end

    {name, attrs, inner}
  end

  # Attribute names mapped to the role they play in the preview. Hosts name
  # things variously, so each role takes the common synonyms; the first
  # match on the tag wins.
  #
  # There is no schema to consult — Leaf has never seen the host's `<Hero>`
  # — so this is a convention, not a contract. Getting it wrong costs
  # nothing: an unrecognised attribute falls through to the source line at
  # the bottom, which is exactly where it was before.
  @role_title ~w(title heading headline name)
  @role_eyebrow ~w(kicker eyebrow overline badge category)
  # `alt` earns a role because on a media component it is usually the only
  # human-written thing on the tag.
  @role_subtitle ~w(subtitle subheading tagline description summary caption blurb text body alt)
  @role_link ~w(href url link to)
  @role_cta ~w(label cta button action)

  # These name a picture outright, so any URL-ish value is taken at face
  # value — real image URLs routinely have no extension (CDN paths, signed
  # URLs, `placehold.co/200x80/png`), and demanding one means most real
  # content gets no thumbnail.
  @preserved_image_attrs ~w(image img poster thumbnail thumb cover background bg avatar photo banner)
  # `src` is ambiguous — `<Audio src="…mp3">` uses it too — so it has to
  # actually look like an image before we draw one.
  @preserved_src_attrs ~w(src)
  @url_ref_re ~r{^(?:https?://|/|\./|data:)\S*$}i
  @image_ref_re ~r{^(?:data:image/|.*\.(?:png|jpe?g|gif|webp|avif|svg)(?:[?#]|$))}i

  # Sort a tag's attributes into display roles, keeping whatever is left
  # over so nothing is silently dropped.
  defp attribute_roles(attrs) do
    media = Enum.find_value(attrs, "", fn attr -> if image_attr?(attr), do: elem(attr, 1) end)
    link = take_role(attrs, @role_link)
    cta = take_role(attrs, @role_cta)

    # `label` is a title on its own and a button caption next to a
    # destination — the same word doing two jobs, disambiguated by whether
    # there is anywhere to go.
    {title, cta_label} =
      case {take_role(attrs, @role_title), cta, link} do
        {"", label, ""} -> {label, ""}
        {"", label, _link} -> {"", label}
        {title, label, _} -> {title, label}
      end

    claimed =
      [
        title,
        cta_label,
        link,
        media,
        take_role(attrs, @role_eyebrow),
        take_role(attrs, @role_subtitle)
      ]
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    %{
      title: title,
      eyebrow: take_role(attrs, @role_eyebrow),
      subtitle: take_role(attrs, @role_subtitle),
      media: media,
      # Any source-ish attribute, URL-shaped or not. Never drawn as a
      # picture — it exists so an inline chip can fall back to a filename
      # rather than render as a bare tag name.
      source: take_role(attrs, @preserved_image_attrs ++ @preserved_src_attrs),
      link: link,
      cta_label: cta_label,
      rest: Enum.reject(attrs, fn {_k, v} -> v in claimed end)
    }
  end

  defp take_role(attrs, names) do
    Enum.find_value(attrs, "", fn {k, v} ->
      if String.downcase(k) in names and String.trim(v) != "", do: v
    end)
  end

  defp url_ref?(value), do: Regex.match?(@url_ref_re, value)

  defp image_attr?({key, value}) do
    key = String.downcase(key)

    cond do
      not Regex.match?(@url_ref_re, value) -> false
      key in @preserved_image_attrs -> true
      key in @preserved_src_attrs -> Regex.match?(@image_ref_re, value)
      true -> false
    end
  end

  # The last path segment of a URL — the only part of `https://cdn…/a/b/
  # hero-2x.png?v=3` a person actually reads.
  defp file_label(""), do: ""

  defp file_label(url) do
    url
    |> String.split(["?", "#"])
    |> hd()
    |> String.split("/")
    |> List.last()
    |> Kernel.||("")
  end

  defp preserved_inner_preview(inner) do
    case String.trim(inner) do
      "" -> ""
      trimmed -> ~s(<span class="leaf-atomic-body">#{render_inner_markdown(trimmed)}</span>)
    end
  end

  # A preserved tag's children rendered as formatted text — this is what
  # makes the bold, the links and the images inside `<Header>…</Header>`
  # visible while writing.
  #
  # Two deliberate restrictions. `unsafe: false` means raw HTML in the
  # children is dropped rather than injected, so a nested custom tag can't
  # recurse back into the chip machinery or smuggle markup into the
  # preview. And the `<p>` wrappers are unwrapped because the block chip
  # is phrasing content living inside MDEx's own `<p>` — a nested `<p>`
  # would close it and split the chip in half.
  defp render_inner_markdown(source) do
    case MDEx.to_html(source, render: [hardbreaks: true, unsafe: false]) do
      {:ok, html} ->
        html
        |> String.replace(~r{<!--\s*raw HTML omitted\s*-->}i, "")
        |> String.replace(~r{</p>\s*<p>}, "<br>")
        |> String.replace(~r{^\s*<p>|</p>\s*$}, "")
        |> flatten_block_children()
        # The chip is not editable, but a real `href` inside a
        # contenteditable is still a live target for ctrl-click and drag.
        # Keep the look, drop the destination.
        |> String.replace(~r/<a\s+href=/i, ~s(<a data-leaf-href=))
        |> String.trim()

      {:error, _} ->
        escape_text(source)
    end
  end

  # The chip is phrasing content inside MDEx's `<p>`, so a heading, list or
  # quote in a tag's body cannot stay a block: the HTML parser closes the
  # `<p>` at the first one and the chip falls apart — its nameplate and
  # attributes land AFTER the body, outside the box. Each block becomes an
  # inline element that is still shown on its own line.
  defp flatten_block_children(html) do
    html
    |> String.replace(
      ~r{<h[1-6][^>]*>(.*?)</h[1-6]>\s*}is,
      ~s(<strong class="leaf-atomic-h">\\1</strong><br>)
    )
    |> String.replace(
      ~r{<li[^>]*>(.*?)</li>\s*}is,
      ~s(<span class="leaf-atomic-li">\\1</span><br>)
    )
    |> String.replace(~r{</?(?:ul|ol)[^>]*>\s*}i, "")
    |> String.replace(~r{<blockquote[^>]*>\s*}i, ~s(<span class="leaf-atomic-quote">))
    |> String.replace(~r{\s*</blockquote>\s*}i, "</span><br>")
    |> String.replace(
      ~r{<pre[^>]*>\s*(?:<code[^>]*>)?(.*?)(?:</code>)?\s*</pre>\s*}is,
      ~s(<code class="leaf-atomic-pre">\\1</code><br>)
    )
    |> String.replace(~r{<hr\s*/?>\s*}i, "<br>")
    # A paragraph after a heading or list is not the first or last one, so
    # the unwrapping above never saw it.
    |> String.replace(~r{<p[^>]*>}i, "")
    |> String.replace(~r{</p>\s*}i, "<br>")
    |> String.replace(~r/(?:<br\s*\/?>\s*){2,}/i, "<br>")
    |> String.replace(~r{(?:<br\s*/?>\s*)+$}i, "")
  end

  defp preserved_tooltip(raw) do
    truncate(String.replace(raw, ~r/\s+/, " "), 200)
  end

  defp truncate(value, max) do
    string = to_string(value)

    if String.length(string) > max do
      String.slice(string, 0, max - 1) <> "…"
    else
      string
    end
  end

  @doc false
  def escape_attr(value) do
    value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  @doc false
  def escape_text(value), do: escape_attr(value)
end
