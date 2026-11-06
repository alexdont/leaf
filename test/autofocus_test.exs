defmodule Leaf.AutofocusTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "off by default, on when asked" do
    refute render_component(Leaf, id: "e1") =~ ~s(data-autofocus="true")
    assert render_component(Leaf, id: "e1", autofocus: true) =~ ~s(data-autofocus="true")
  end
end
