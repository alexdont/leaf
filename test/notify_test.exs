defmodule Leaf.NotifyTest do
  @moduledoc """
  `notify: {module, id}` sends Leaf's messages to a LiveComponent instead of the
  LiveView. A component shares its LiveView's process, so an editor inside one
  used to send everything to the host page — which crashed on it without a
  catch-all `handle_info`.
  """
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket

  defmodule Panel do
    # Stands in for the component that hosts the editor.
  end

  defp socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}, id: "editor-1", deny: []}, Map.new(assigns))
    }
  end

  defp changed(socket) do
    Leaf.handle_event("content_changed", %{"markdown" => "# hi", "html" => "<h1>hi</h1>"}, socket)
  end

  test "without notify, messages go to the LiveView as before" do
    changed(socket([]))

    assert_received {:leaf_changed, %{editor_id: "editor-1", markdown: "# hi"}}
    refute_received {:phoenix, :send_update, _}
  end

  test "with notify, they go to the component, as a :leaf assign" do
    changed(socket(notify: {Panel, "notes"}))

    assert_received {:phoenix, :send_update,
                     {{Panel, "notes"},
                      %{
                        id: "notes",
                        leaf: {:leaf_changed, %{editor_id: "editor-1", markdown: "# hi"}}
                      }}}

    refute_received {:leaf_changed, _}
  end

  test "every kind of message follows notify, not just content changes" do
    socket = socket(notify: {Panel, "notes"}, emit_events: true)

    Leaf.handle_event("focus", %{}, socket)
    Leaf.handle_event("blur", %{}, socket)

    assert_received {:phoenix, :send_update, {{Panel, "notes"}, %{leaf: {:leaf_focus, _}}}}
    assert_received {:phoenix, :send_update, {{Panel, "notes"}, %{leaf: {:leaf_blur, _}}}}
    refute_received {:leaf_focus, _}
    refute_received {:leaf_blur, _}
  end

  test "a flush reply follows notify" do
    Leaf.handle_event(
      "flushed",
      %{"ref" => "r1", "markdown" => "x", "html" => "<p>x</p>"},
      socket(notify: {Panel, "notes"})
    )

    assert_received {:phoenix, :send_update,
                     {{Panel, "notes"}, %{leaf: {:leaf_flushed, %{ref: "r1"}}}}}
  end

  test "a malformed notify is refused when the editor is set up" do
    assert_raise ArgumentError, ~r/notify/, fn ->
      Leaf.update(%{id: "editor-1", content: "", notify: "Panel"}, socket([]))
    end
  end

  test "notify is accepted when the editor is set up" do
    assert {:ok, socket} =
             Leaf.update(%{id: "editor-1", content: "", notify: {Panel, "notes"}}, socket([]))

    assert socket.assigns.notify == {Panel, "notes"}
  end
end
