defmodule Leaf.CollabTest do
  @moduledoc """
  The host-side half of live editing, driven through the hook `join/2`
  attaches rather than through a running LiveView.
  """
  use ExUnit.Case, async: false

  alias Leaf.Collab.Room
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket

  @doc_with_links "see [docs](https://example.com) now"

  setup do
    name = :"collab-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Room,
       name: name, pubsub: Leaf.TestPubSub, document_id: "t", initial_content: @doc_with_links},
      id: name
    )

    %{room: name}
  end

  defp joined(room, opts) do
    socket = %Socket{
      assigns: %{__changed__: %{}},
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }

    Leaf.Collab.join(socket, [room: room, editor_id: "e"] ++ opts)
  end

  defp ready(socket, markdown, revision) do
    Lifecycle.handle_info(
      {:leaf_ready, %{markdown: markdown, revision: revision}},
      socket
    )
  end

  describe "an editor with a deny list" do
    test "showing the document without its links is not taken for a rewrite", %{room: room} do
      socket = joined(room, deny: [:links])
      %{revision: revision} = Room.snapshot(room)

      assert {:halt, _} = ready(socket, "see docs now", revision)

      assert Room.snapshot(room).document == @doc_with_links,
             "the links must still be there for everyone else"
    end

    test "writing the room never saw is still adopted", %{room: room} do
      socket = joined(room, deny: [:links])
      %{revision: revision} = Room.snapshot(room)

      assert {:halt, _} = ready(socket, "see docs now, and more", revision)

      assert Room.snapshot(room).document == "see docs now, and more"
    end
  end
end
