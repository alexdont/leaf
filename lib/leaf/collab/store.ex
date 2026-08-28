defmodule Leaf.Collab.Store do
  @moduledoc """
  Where a live document comes from, and where it goes.

  A room holds a document while people are editing it, and that is all it does
  — it lives in memory and dies with the process. Anything anyone would mind
  losing needs somewhere to go, and where is not a decision this code can make:
  a file, a table, an object store and a queue all make sense for different
  hosts. So it is a callback.

  The lifecycle follows the collaboration spec:

    * **hydrate** — `c:load/1` on the first open. Whatever comes back is the
      document; `:error` means start from nothing.
    * **edit** — `c:save/2` on every change. Meant for a store cheap enough to
      write to constantly, so a crash loses seconds rather than work. A host
      with no such store makes this a no-op.
    * **flush** — `c:flush/2` after the writing has paused, and again if it has
      been going on long enough that waiting for a pause would mean waiting too
      long. Meant for the expensive, canonical copy — the `.md` file in a vault.
      Always called once more on the way down.

  The split matters: writing a file on every keystroke is wasteful, and only
  writing it when everyone leaves means a crash costs the session. Two
  callbacks let a host have both.

  ## Conflict

  `c:flush/2` may answer `{:error, :conflict}` when the destination changed
  underneath the session — someone edited the file directly while it was open.
  The room keeps the document and stops flushing rather than overwriting work
  it did not make; resolving it is the host's business, since only the host
  knows what the other copy is.
  """

  @typedoc "What a room holds and what is restored to it."
  @type snapshot :: %{document: String.t(), revision: non_neg_integer()}

  @doc "The document to start from, or `:error` to start empty."
  @callback load(id :: String.t()) :: {:ok, snapshot()} | :error

  @doc "Record a change. Called often; make it cheap or make it a no-op."
  @callback save(id :: String.t(), snapshot()) :: :ok | {:error, term()}

  @doc """
  Write the canonical copy.

  Called when the writing pauses, at a bounded interval while it continues, and
  once when the room stops.
  """
  @callback flush(id :: String.t(), snapshot()) :: :ok | {:error, :conflict} | {:error, term()}
end
