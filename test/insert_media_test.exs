defmodule Leaf.InsertMediaTest do
  # The image/video round trip with the host: the editor asks
  # (`insert_request`), the host answers with `send_update(Leaf, action:
  # :insert_image, …)`, and that reaches the browser as a `leaf-command`.
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket

  defp socket(assigns \\ %{}) do
    %Socket{assigns: Map.merge(%{__changed__: %{}, id: "ed", deny: []}, assigns)}
  end

  defp pushed(socket), do: socket.private.live_temp.push_events

  describe "the editor asking" do
    test "an image request reaches the parent with the editor's id" do
      assert {:noreply, _} =
               Leaf.handle_event("insert_request", %{"type" => "image"}, socket())

      assert_received {:leaf_insert_request, %{editor_id: "ed", type: :image}}
    end

    test "a request with no type is ignored" do
      assert {:noreply, _} = Leaf.handle_event("insert_request", %{}, socket())
      refute_received {:leaf_insert_request, _}
    end
  end

  describe "the host answering" do
    test "insert_image is pushed to this editor with its URL and alt" do
      {:ok, socket} =
        Leaf.update(
          %{action: :insert_image, url: "https://img.example/a.png", alt: "a cat"},
          socket()
        )

      assert [
               [
                 "leaf-command:ed",
                 %{action: "insert_image", url: "https://img.example/a.png", alt: "a cat"}
               ]
             ] =
               pushed(socket)
    end

    test "alt defaults to empty" do
      {:ok, socket} = Leaf.update(%{action: :insert_image, url: "/a.png"}, socket())
      assert [["leaf-command:ed", %{alt: ""}]] = pushed(socket)
    end

    test "the command is addressed to this editor only" do
      {:ok, socket} = Leaf.update(%{action: :insert_image, url: "/a.png"}, socket(%{id: "other"}))
      assert [["leaf-command:other", _]] = pushed(socket)
    end
  end
end
