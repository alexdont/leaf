defmodule Leaf.Collab.Text do
  @moduledoc """
  The unit an operation's offsets are counted in.

  An editor describes its edit with the numbers its own strings give it:
  `at` and `remove` from JavaScript's `length` and `slice`, which count
  UTF-16 code units. `String.length/1` counts graphemes, and the two agree
  only while the text has nothing outside the Basic Multilingual Plane and
  no combining marks — one emoji, and every offset after it is off by one for
  the room, which then refuses or misplaces every edit. So the room measures
  and cuts the document in the editor's unit.
  """

  @doc "Length in UTF-16 code units."
  @spec length(String.t()) :: non_neg_integer()
  def length(text) when is_binary(text), do: div(byte_size(utf16(text)), 2)

  @doc """
  Replaces `remove` code units at `at` with `insert`.

  `:error` when the splice points outside the text or would cut a surrogate
  pair in half — neither can be applied without scattering characters.
  """
  @spec splice(String.t(), integer(), integer(), String.t()) :: {:ok, String.t()} | :error
  def splice(text, at, remove, insert)
      when is_binary(text) and is_integer(at) and is_integer(remove) and is_binary(insert) and
             at >= 0 and remove >= 0 do
    bin = utf16(text)
    stop = (at + remove) * 2

    if stop <= byte_size(bin) do
      head = binary_part(bin, 0, at * 2)
      tail = binary_part(bin, stop, byte_size(bin) - stop)

      case :unicode.characters_to_binary(head <> utf16(insert) <> tail, {:utf16, :big}, :utf8) do
        result when is_binary(result) -> {:ok, result}
        _ -> :error
      end
    else
      :error
    end
  end

  def splice(_text, _at, _remove, _insert), do: :error

  @doc "The text as big-endian UTF-16, two bytes per code unit."
  @spec utf16(String.t()) :: binary()
  def utf16(text) when is_binary(text) do
    case :unicode.characters_to_binary(text, :utf8, {:utf16, :big}) do
      bin when is_binary(bin) -> bin
      # Invalid UTF-8 cannot come from JSON; keep what converts.
      {_, converted, _} -> converted
    end
  end
end
