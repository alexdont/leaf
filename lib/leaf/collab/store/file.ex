defmodule Leaf.Collab.Store.File do
  @moduledoc """
  A markdown file on disk, which is what a vault of notes actually is.

  The reference implementation, and the one the collaboration spec describes:
  with nobody editing, the file is the document; while a session is live, the
  room holds it and the file is a lagging export.

  `save/2` does nothing here. A file is the expensive copy, not the cheap one —
  writing it on every keystroke would be wasteful and would defeat the point of
  having two callbacks. A host wanting to lose seconds rather than a session
  puts a row in a table behind `save/2` and keeps this behaviour for `flush/2`.

  ## Edits made behind the session's back

  The hash of the file is recorded when it is read, and checked again before it
  is written. If it changed in between, somebody edited the note outside the
  editor and the two copies have both moved. That is answered with
  `{:error, :conflict}` rather than a write: the work in the file is somebody's,
  and this session's copy is not more entitled to exist than theirs.

  Reconciling them needs a person, or at least a policy, and neither belongs in
  a store.
  """
  @behaviour Leaf.Collab.Store

  @doc "Where a document with this id lives. Public so a host can configure it."
  def path(id), do: Path.join(root(), id <> ".md")

  def root do
    Application.get_env(:leaf, __MODULE__, [])[:root] ||
      raise """
      Leaf.Collab.Store.File needs to know where the notes live:

          config :leaf, Leaf.Collab.Store.File, root: "/path/to/vault"

      Refusing to guess: a default would write somebody's notes somewhere they
      did not ask for and would not think to look.
      """
  end

  @impl true
  def load(id) do
    case File.read(path(id)) do
      {:ok, contents} ->
        remember_hash(id, contents)
        {:ok, %{document: contents, revision: 0}}

      {:error, _} ->
        # Nothing on disk is not a failure: it is a note that has not been
        # written yet. Remember that, so the first flush knows it is creating
        # rather than overwriting.
        remember_hash(id, nil)
        :error
    end
  end

  @impl true
  def save(_id, _snapshot), do: :ok

  @impl true
  def flush(id, %{document: document}) do
    path = path(id)

    with :ok <- check_unchanged(id, path),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, document) do
      remember_hash(id, document)
      :ok
    end
  end

  # What was on disk when we last read or wrote it. Held in the process
  # dictionary of the room that owns this document — one room per document, and
  # nothing else has any business knowing.
  defp remember_hash(id, contents), do: Process.put({__MODULE__, id}, hash(contents))

  defp check_unchanged(id, path) do
    known = Process.get({__MODULE__, id}, :unknown)

    current =
      case File.read(path) do
        {:ok, contents} -> hash(contents)
        {:error, _} -> nil
      end

    cond do
      # Never read it, so nothing to compare against. Writing is the only
      # sensible thing, and refusing would strand the document in memory.
      known == :unknown -> :ok
      known == current -> :ok
      true -> {:error, :conflict}
    end
  end

  defp hash(nil), do: nil
  defp hash(contents), do: :crypto.hash(:sha256, contents)
end
