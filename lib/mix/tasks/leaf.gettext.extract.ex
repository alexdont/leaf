defmodule Mix.Tasks.Leaf.Gettext.Extract do
  @shortdoc "Regenerate priv/gettext/leaf.pot from the t(\"…\") calls in Leaf's source"

  @moduledoc """
  Regenerates `priv/gettext/leaf.pot`.

  Leaf's translatable strings go through a bare `t/1` rather than a Gettext
  macro, so `mix gettext.extract` has nothing to hook into — and a host app
  can't extract msgids out of a dependency's source anyway. This scans
  `lib/leaf.ex` and `lib/leaf/` for `t("…")` calls and writes the catalog template hosts
  merge into their own.

      mix leaf.gettext.extract

  `Leaf.GettextPotTest` fails when the shipped file is out of date, so a
  new string in the template is caught before it ships untranslatable.
  """

  use Mix.Task

  alias Leaf.Gettext.Pot

  @target "priv/gettext/leaf.pot"

  @impl Mix.Task
  def run(_args) do
    File.mkdir_p!(Path.dirname(@target))
    File.write!(@target, Pot.render(Pot.source()))
    Mix.shell().info("Wrote #{@target}")
  end
end
