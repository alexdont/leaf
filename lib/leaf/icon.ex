defmodule Leaf.Icon do
  @moduledoc """
  Built-in icon component using the heroicons span pattern.

  Requires heroicons CSS classes (e.g. `hero-bold`) to be available in your app.
  """

  use Phoenix.Component

  attr(:name, :string, required: true)
  attr(:class, :string, default: nil)

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def icon(assigns) do
    ~H"""
    """
  end
end
