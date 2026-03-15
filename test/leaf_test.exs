defmodule LeafTest do
  use ExUnit.Case

  test "Leaf module is loaded" do
    assert Code.ensure_loaded?(Leaf)
  end

  test "Leaf.Icon module is loaded" do
    assert Code.ensure_loaded?(Leaf.Icon)
  end
end
