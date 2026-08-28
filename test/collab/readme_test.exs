defmodule Leaf.Collab.ReadmeTest do
  @moduledoc """
  The quickstart in the README, run.

  Documentation that has never been executed is a guess about your own API.
  This starts a room the way the README says to, with the options it names, and
  checks the store contract it shows compiles and is called.
  """
  use ExUnit.Case, async: false

  alias Leaf.Collab.Room
  alias Leaf.Collab.Store

  # Exactly the shape the README puts in front of a reader.
  defmodule NoteStore do
    @behaviour Leaf.Collab.Store

    @impl true
    def load(_id), do: :error

    @impl true
    def save(_id, _snapshot), do: :ok

    # Reports back to the test rather than writing anywhere: a store runs in
    # the room's process, so anything it puts in a process dictionary is
    # invisible from here.
    @impl true
    def flush(id, snapshot) do
      send(:leaf_readme_observer, {:flushed, id, snapshot.document})
      :ok
    end
  end

  test "a room starts with the options the README names" do
    name = :"readme-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Room,
       name: name,
       pubsub: Leaf.TestPubSub,
       document_id: "note-1",
       initial_content: "# A note\n\nwritten already",
       store: NoteStore},
      id: name
    )

    assert Room.snapshot(name).document == "# A note\n\nwritten already"
  end

  test "the room tells you where its sessions hear about each other" do
    name = :"readme-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Room, name: name, pubsub: Leaf.TestPubSub, document_id: "note-2"},
      id: name
    )

    info = Room.info(name)

    assert info.pubsub == Leaf.TestPubSub
    assert info.document_id == "note-2"
    assert is_binary(info.topic), "a host does not have to invent one"
  end

  test "the timings the README documents are the ones it takes" do
    Process.register(self(), :leaf_readme_observer)
    name = :"readme-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Room,
       name: name,
       pubsub: Leaf.TestPubSub,
       document_id: "note-3",
       flush_after: 25,
       flush_at_most_every: 60,
       store: NoteStore},
      id: name
    )

    Room.apply_operation(name, "A", %{
      at: 0,
      remove: 0,
      insert: "hello",
      rendered: nil,
      revision: nil,
      base_length: nil
    })

    # Named options, not ignored ones: a pause writes without being asked.
    assert_receive {:flushed, "note-3", "hello" <> _}, 2_000
  end

  # The other half of what the README promises: nothing is kept by default.
  test "the default store keeps nothing" do
    assert Store.None.load("anything") == :error
  end

  defp eventually(check, attempts \\ 100) do
    Enum.reduce_while(1..attempts, false, fn _, _ ->
      if check.() do
        {:halt, true}
      else
        Process.sleep(10)
        {:cont, false}
      end
    end)
  end
end
