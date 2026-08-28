defmodule Leaf.Collab.Store.None do
  @moduledoc """
  Keeps nothing.

  The default, and the right one for a document nobody minds losing: a
  scratch pad, a demo, a draft that lives as long as the people looking at it.

  It is also the honest default for a host that has not said where its
  documents live. Better a room that admits it stores nothing than one that
  quietly loses work it appeared to have saved.
  """
  @behaviour Leaf.Collab.Store

  @impl true
  def load(_id), do: :error

  @impl true
  def save(_id, _snapshot), do: :ok

  @impl true
  def flush(_id, _snapshot), do: :ok
end
