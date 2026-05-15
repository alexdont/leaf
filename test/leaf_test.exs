defmodule LeafTest do
  use ExUnit.Case

  test "Leaf module is loaded" do
    assert Code.ensure_loaded?(Leaf)
  end
end
