defmodule Mix.Tasks.Quality do
  @moduledoc "Runs format check, credo, and dialyzer."
  @shortdoc "Runs format, credo, and dialyzer"

  use Mix.Task

  @impl true
  def run(_args) do
    tasks = [
      {"mix format --check-formatted", "Format check"},
      {"mix credo --strict", "Credo"},
      {"mix dialyzer", "Dialyzer"}
    ]

    Enum.each(tasks, fn {cmd, label} ->
      Mix.shell().info("\n==> #{label}")

      case Mix.shell().cmd(cmd) do
        0 -> :ok
        _ -> Mix.raise("#{label} failed")
      end
    end)

    Mix.shell().info("\nAll quality checks passed!")
  end
end
