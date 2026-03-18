defmodule Leaf.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/alexdont/leaf"

  def project do
    [
      app: :leaf,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Leaf",
      description: "Dual-mode visual WYSIWYG + markdown editor for Phoenix LiveView",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      dialyzer: [plt_add_apps: [:mix]]
    ]
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
      {:earmark, "~> 1.4"},
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
      files: ~w(lib priv/static/assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
