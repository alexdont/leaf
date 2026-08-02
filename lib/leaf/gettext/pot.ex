defmodule Leaf.Gettext.Pot do
  @moduledoc """
  Renders `priv/gettext/leaf.pot` from Leaf's source.

  Split out of the mix task so a test can assert the shipped file is
  current without shelling out — a new toolbar string that never reaches
  the catalog ships untranslatable, and nobody notices until a host asks
  why half the editor is still in English.
  """

  @header """
  ## Leaf editor UI strings.
  ##
  ## Leaf's msgids live in a dependency's source, which a host's
  ## `mix gettext.extract` cannot see. Copy this file into your own
  ## `priv/gettext/` and run `mix gettext.merge priv/gettext` to get
  ## `<locale>/LC_MESSAGES/leaf.po` files to translate.
  ##
  ## Leaf looks up the "leaf" domain first and falls back to "default", so
  ## you can also paste these msgids into `default.pot` instead if you would
  ## rather keep one catalog.
  ##
  ## Regenerate with `mix leaf.gettext.extract`.
  msgid ""
  msgstr ""
  "Language: \\n"
  "Plural-Forms: nplurals=2\\n"
  """

  @doc """
  The full `.pot` contents for the given Elixir source.
  """
  @spec render(String.t()) :: String.t()
  def render(source) do
    entries =
      source
      |> msgids()
      |> Enum.map_join("", fn msgid -> "\nmsgid \"#{escape(msgid)}\"\nmsgstr \"\"\n" end)

    @header <> entries
  end

  @doc """
  Every `t("…")` msgid in `source`, deduplicated and sorted.
  """
  @spec msgids(String.t()) :: [String.t()]
  def msgids(source) do
    ~r/\bt\("((?:[^"\\]|\\.)*)"\)/
    |> Regex.scan(source, capture: :all_but_first)
    |> Enum.map(fn [literal] -> unescape(literal) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp escape(string) do
    string |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
  end

  defp unescape(literal) do
    literal |> String.replace("\\\"", "\"") |> String.replace("\\\\", "\\")
  end
end
