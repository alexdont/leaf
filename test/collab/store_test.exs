defmodule Leaf.Collab.StoreTest do
  @moduledoc """
  Persistence, exercised rather than assumed.

  The testbed stores nothing on purpose — its document is a scratch pad. But
  code nobody runs is code nobody has checked, and this is the code a host will
  trust its notes to, so it is driven against a real file here.
  """
  use ExUnit.Case, async: false

  alias Leaf.Collab.Room
  alias Leaf.Collab.Store

  @content "# Note\n\nsomething already written"

  # Counts what it was asked to do, so "was this written" can be answered
  # exactly rather than by looking at a file's timestamp, whose resolution is a
  # whole second.
  defmodule Recorder do
    @behaviour Leaf.Collab.Store

    def start, do: Agent.start_link(fn -> %{saves: 0, flushes: 0} end, name: __MODULE__)

    def reset do
      start()
      Agent.update(__MODULE__, fn _ -> %{saves: 0, flushes: 0} end)
    end

    def saves, do: Agent.get(__MODULE__, & &1.saves)
    def flushes, do: Agent.get(__MODULE__, & &1.flushes)

    @impl true
    def load(_id), do: :error

    @impl true
    def save(_id, _snapshot) do
      Agent.update(__MODULE__, &%{&1 | saves: &1.saves + 1})
      :ok
    end

    @impl true
    def flush(_id, _snapshot) do
      Agent.update(__MODULE__, &%{&1 | flushes: &1.flushes + 1})
      :ok
    end
  end

  setup context do
    root = Path.join(System.tmp_dir!(), "collab-store-#{:erlang.phash2(context.test)}")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    Application.put_env(:leaf, Store.File, root: root)

    on_exit(fn ->
      File.rm_rf!(root)
      Application.delete_env(:leaf, Store.File)
    end)

    %{root: root, id: "note"}
  end

  describe "the file store" do
    test "a note that has not been written yet is not a failure", %{id: id} do
      assert Store.File.load(id) == :error
    end

    test "what was written is what comes back", %{id: id} do
      assert :ok = Store.File.flush(id, %{document: "# Note\n\nbody", revision: 3})
      assert {:ok, %{document: "# Note\n\nbody"}} = Store.File.load(id)
    end

    test "a note edited outside the session is not overwritten", %{root: root, id: id} do
      assert :ok = Store.File.flush(id, %{document: "ours", revision: 1})
      assert {:ok, _} = Store.File.load(id)

      # Somebody edits the file directly while the session is open.
      File.write!(Path.join(root, "#{id}.md"), "theirs, written elsewhere")

      assert {:error, :conflict} =
               Store.File.flush(id, %{document: "ours, changed again", revision: 2})

      assert File.read!(Path.join(root, "#{id}.md")) == "theirs, written elsewhere",
             "their work must still be there"
    end

    test "writing again after reading our own write is not a conflict", %{id: id} do
      assert :ok = Store.File.flush(id, %{document: "one", revision: 1})
      assert :ok = Store.File.flush(id, %{document: "two", revision: 2})
      assert {:ok, %{document: "two"}} = Store.File.load(id)
    end
  end

  describe "a room with somewhere to put things" do
    test "opens on what the store already has", %{root: root, id: id} do
      File.write!(Path.join(root, "#{id}.md"), "written earlier")

      room = start_room(id)

      assert Room.snapshot(room).document == "written earlier"
    end

    test "starts from the opening text when the store has nothing", %{id: id} do
      room = start_room(id)

      assert Room.snapshot(room).document ==
               @content
    end

    test "writes what was typed", %{root: root, id: id} do
      room = start_room(id)

      Room.apply_operation(room, "A", op(0, 1, "@"))
      Room.flush_now(room)

      assert File.read!(Path.join(root, "#{id}.md")) == Room.snapshot(room).document
    end

    # The reason a room is stopped rather than killed.
    test "writes on the way down without being asked", %{root: root, id: id} do
      room = start_room(id)
      Room.apply_operation(room, "A", op(0, 1, "%"))

      # Nothing on disk yet: the timers have not fired.
      refute File.exists?(Path.join(root, "#{id}.md"))

      GenServer.stop(room)

      assert File.read!(Path.join(root, "#{id}.md")) =~ "% Note",
             "the last thing a room does is write down what it was holding"
    end

    # The timer, not flush_now: the point is that a host gets a write without
    # asking for one.
    test "a pause in the typing writes by itself", %{root: root, id: id} do
      room = start_room(id, flush_after: 20)
      Room.apply_operation(room, "A", op(0, 1, "&"))

      path = Path.join(root, "#{id}.md")
      assert eventually(fn -> File.exists?(path) end), "the pause should have written it"
      assert File.read!(path) =~ "& Note"
    end

    # Someone typing steadily never pauses, so waiting for one would mean never
    # writing at all.
    test "writing that does not pause is still written", %{root: root, id: id} do
      room = start_room(id, flush_after: 10_000, flush_at_most_every: 30)

      # Each change pushes the pause further away; only the cap gets us a write.
      for i <- 1..5 do
        Room.apply_operation(room, "A", op(0, 0, "#{i}"))
        Process.sleep(10)
      end

      path = Path.join(root, "#{id}.md")
      assert eventually(fn -> File.exists?(path) end), "the cap should have forced a write"
    end

    test "nothing is written when nothing changed", %{id: id} do
      room = start_room(id, store: Recorder)
      Recorder.reset()

      Room.apply_operation(room, "A", op(0, 1, "="))
      Room.flush_now(room)
      assert Recorder.flushes() == 1

      Room.flush_now(room)
      assert Recorder.flushes() == 1, "a room with nothing new to say must stay quiet"
    end

    test "every change reaches the cheap store, not only the flush", %{id: id} do
      room = start_room(id, store: Recorder)
      Recorder.reset()

      for _ <- 1..3, do: Room.apply_operation(room, "A", op(0, 0, "x"))

      assert Recorder.saves() == 3, "save/2 is what makes a crash cost seconds"
    end
  end

  # A store talks to somebody else's disk or database and can be unavailable at
  # exactly the moment it is needed. Taking the room down with it would lose
  # the document outright, which is the one outcome worth avoiding.
  describe "a store that fails" do
    defmodule Broken do
      @behaviour Leaf.Collab.Store

      @impl true
      def load(_id), do: :error

      @impl true
      def save(_id, _snapshot), do: raise("the database is not there")

      @impl true
      def flush(_id, _snapshot), do: raise("the disk is full")
    end

    test "does not take the room with it", %{id: id} do
      name = :"broken-#{System.unique_integer([:positive])}"

      start_supervised!(
        {Room,
         name: name,
         pubsub: Leaf.TestPubSub,
         store: Broken,
         document_id: id,
         initial_content: @content},
        id: name
      )

      Room.apply_operation(name, "A", op(0, 1, "@"))
      Room.flush_now(name)

      assert Process.whereis(name), "the room must still be there"

      assert Room.snapshot(name).document =~ "@ Note",
             "and must still be holding the writing"
    end

    test "leaves the document unsaved so a later attempt can try again", %{id: id} do
      name = :"broken-#{System.unique_integer([:positive])}"

      start_supervised!(
        {Room,
         name: name,
         pubsub: Leaf.TestPubSub,
         store: Broken,
         document_id: id,
         initial_content: @content},
        id: name
      )

      Room.apply_operation(name, "A", op(0, 1, "@"))
      Room.flush_now(name)

      # Still editable, still consistent: a failed write is not a lost room.
      Room.apply_operation(name, "A", op(0, 0, "!"))
      assert String.starts_with?(Room.snapshot(name).document, "!@")
    end
  end

  test "the default store keeps nothing" do
    assert Store.None.load("testbed") == :error
    assert Store.None.flush("testbed", %{document: "x", revision: 1}) == :ok
  end

  defp start_room(id, opts \\ []) do
    name = :"room-#{id}-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Room,
       [
         name: name,
         pubsub: Leaf.TestPubSub,
         store: Store.File,
         document_id: id,
         initial_content: @content
       ]
       |> Keyword.merge(opts)},
      id: name
    )

    name
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

  defp op(at, remove, insert),
    do: %{at: at, remove: remove, insert: insert, rendered: nil, revision: nil, base_length: nil}
end
