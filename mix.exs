defmodule Leaf.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/alexdont/leaf"

  def project do
    [
      app: :leaf,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Leaf",
      description:
        "Visual WYSIWYG + Obsidian-style hybrid live preview + markdown editor for Phoenix LiveView",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      dialyzer: [plt_add_apps: [:mix]],
      aliases: aliases()
    ]
  end

  defp aliases do
    [
      # The undo/redo stack is real logic living in the JS bundle, so the
      # Elixir suite alone no longer covers this library. Runs after it, and
      # skips rather than fails where node is unavailable — the Elixir tests
      # remain the gate.
      test: ["test", "test.js"],
      "test.js": &run_js_tests/1
    ]
  end

  # `node --test` over the shipped hook bundle. Files are passed explicitly:
  # with no arguments node walks the CWD looking for anything test-shaped,
  # which would hand it deps/, _build/ and node_modules/ as well.
  #
  # `*_dom.test.cjs` drive the editor against a real DOM and need jsdom, a
  # devDependency in package.json. Without it they skip themselves with a
  # message, so a clone that never ran `npm install` still passes — the
  # stubbed tests are the floor, the DOM tests are the ones that catch DOM
  # bugs. Install with `npm install` in this directory.
  defp run_js_tests(_args) do
    files = Path.wildcard("test/js/*.test.cjs")

    cond do
      files == [] ->
        Mix.shell().info("[skip] no test/js/*.test.cjs files")

      System.find_executable("node") == nil ->
        Mix.shell().info("[skip] node not found — skipping test/js")

      true ->
        {output, status} = System.cmd("node", ["--test" | files], stderr_to_stdout: true)
        IO.puts(output)
        if status != 0, do: Mix.raise("JS tests failed")
    end
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      # Live editing broadcasts between the sessions in a document. It arrives
      # transitively through phoenix_live_view today, which is luck rather than
      # a contract — Leaf calls it directly, so Leaf asks for it.
      {:phoenix_pubsub, "~> 2.0"},
      {:mdex, "~> 0.13"},
      {:gettext, "~> 0.26 or ~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib priv/static/assets priv/gettext .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
