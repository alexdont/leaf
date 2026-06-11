defmodule LeafTest do
  use ExUnit.Case

  import Phoenix.LiveViewTest

  test "Leaf module is loaded" do
    assert Code.ensure_loaded?(Leaf)
  end

  # Regression for 0.2.24: the :class attr default (added in 0.2.23) was only
  # filled in for function-component calls (<.leaf_editor />). The matching
  # mount/1 assign_new was missed, so <.live_component module={Leaf}> callers
  # who omitted class= crashed with `KeyError: key :class not found` on first
  # render. Rendering the component directly exercises the mount/1 -> update/2
  # -> render/1 path that live_component uses.
  test "renders via live_component path with no attrs beyond :id" do
    html = render_component(Leaf, id: "t")

    assert html =~ ~s(id="t")
    assert html =~ "min-w-0"
  end
end
