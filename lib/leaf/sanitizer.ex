defmodule Leaf.Sanitizer do
  @moduledoc """
  The allow-list rendered markdown passes before it reaches a page.

  Markdown may carry raw HTML, and Leaf writes some itself (figures, details,
  sized images), so the renderer runs with `unsafe: true` — which would also
  let through a `<script>`, an `onerror` or a `javascript:` link typed by
  whoever wrote the document; with live editing that is a collaborator's
  browser. Everything Leaf emits is on the list, nothing that runs code is.

  A host rendering the saved markdown itself can reuse the same list:

      MDEx.to_html!(markdown, render: [unsafe: true], sanitize: Leaf.Sanitizer.options())
  """

  @tags ~w(figure figcaption details summary u mark kbd video audio source span div)

  @tag_attributes %{
    "img" => ~w(width height data-align draggable loading),
    "figure" => ~w(data-align),
    "details" => ~w(open),
    "video" => ~w(src controls width height poster preload loop muted playsinline),
    "audio" => ~w(src controls preload loop),
    "source" => ~w(src type)
  }

  @doc """
  MDEx's `sanitize:` option, extended with the tags, attributes and URL
  schemes Leaf's own markup uses.
  """
  @spec options() :: keyword()
  def options do
    [
      add_tags: @tags,
      add_tag_attributes: @tag_attributes,
      add_generic_attributes: ~w(class contenteditable),
      add_generic_attribute_prefixes: ["data-"],
      add_url_schemes: ~w(mailto tel),
      link_rel: nil
    ]
  end
end
