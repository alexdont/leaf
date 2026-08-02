defmodule Leaf.ShippedArtifactsTest do
  @moduledoc """
  Two files ship alongside the code and can silently drift out of sync
  with it. Both failure modes are invisible at runtime, which is why they
  get a test rather than a convention.
  """
  use ExUnit.Case, async: true

  alias Leaf.Gettext.Pot

  @js_path "priv/static/assets/leaf.js"
  @pot_path "priv/gettext/leaf.pot"

  describe "gettext catalog template" do
    test "is up to date with the t(\"…\") calls in lib/leaf.ex" do
      expected = Pot.render(File.read!("lib/leaf.ex"))

      assert File.read!(@pot_path) == expected, """
      #{@pot_path} is out of date — a UI string was added, changed or removed \
      without regenerating the catalog, so hosts cannot translate it.

      Run: mix leaf.gettext.extract
      """
    end

    test "carries the strings a translator would look for" do
      msgids = Pot.msgids(File.read!("lib/leaf.ex"))

      for expected <- ["Bold", "Italic", "Markdown mode", "Searching…", "Unsaved changes"] do
        assert expected in msgids
      end
    end
  end

  describe "JS bundle version" do
    # The whole point of window.LeafHooks.version is telling a host that a
    # vendored copy of leaf.js is behind the library. A constant that isn't
    # bumped with the release turns that signal into a lie — worse than not
    # having it, because a stale bundle would then report itself current.
    test "matches the library version" do
      declared =
        @js_path
        |> File.read!()
        |> then(&Regex.run(~r/window\.LeafHooks\.version\s*=\s*"([^"]+)"/, &1))
        |> case do
          [_, version] -> version
          _ -> flunk("no window.LeafHooks.version assignment found in #{@js_path}")
        end

      assert declared == Mix.Project.config()[:version], """
      #{@js_path} declares version #{declared} but mix.exs is on \
      #{Mix.Project.config()[:version]}.

      Update the `window.LeafHooks.version` constant near the top of \
      #{@js_path} to match. Leaf.js_version/0 is compared against it at \
      runtime to catch vendored bundles that stayed behind.
      """
    end

    test "Leaf.js_version/0 reports the same version" do
      assert Leaf.js_version() == Mix.Project.config()[:version]
    end
  end
end
