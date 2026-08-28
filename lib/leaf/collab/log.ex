defmodule Leaf.Collab.Log do
  @moduledoc """
  A running account of what each session believes it is holding.

  The point is to make a disagreement visible at the moment it happens rather
  than to be inferred from two tabs of text afterwards. Every operation carries
  the sender's fingerprint of its own document; the room computes the same
  fingerprint over the result of applying that operation. If the two differ,
  the sender and the room have parted company — and the log says so on the line
  where it happened, with the caret positions and revisions in view.

  Only written when a host turns diagnostics on, because it is one line per
  keystroke and a fingerprint of the whole document each time. Useful while
  something is wrong; wasteful once it is not.

  Read it with:

      tail -f your.log | grep '\\[collab\\]'
  """
  require Logger

  @doc """
  FNV-1a, 32 bit, over the document's code points.

  Matches the editor's `_digest` exactly, so the same text produces the same
  eight characters on both sides. Text outside the Basic Multilingual Plane
  hashes differently here than in the browser, which is a limitation of
  comparing UTF-16 code units with code points and not worth more than a note.
  """
  def digest(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(0x811C9DC5, fn char, hash ->
      Bitwise.band(Bitwise.bxor(hash, char) * 0x01000193, 0xFFFFFFFF)
    end)
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(8, "0")
  end

  def operation(session, op, result) do
    debug = Map.get(op, :debug) || %{}

    Logger.info(
      "[collab] op " <>
        fields([
          {"session", session},
          {"seq", Map.get(op, :seq)},
          {"rev", Map.get(op, :revision)},
          {"at", Map.get(op, :at)},
          {"rm", Map.get(op, :remove)},
          {"ins", inspect(Map.get(op, :insert))},
          {"rendered", rendered(Map.get(op, :rendered))},
          {"base_len", Map.get(op, :base_length)},
          {"caret", Map.get(debug, :caret)},
          {"pending", Map.get(debug, :pending)},
          {"outcome", outcome(result)}
        ])
    )
  end

  @doc """
  Compare what the sender ended up with against what the room did.

  Returns `:match`, `:mismatch`, or `:unknown` when the editor sent no
  fingerprint. A mismatch is the moment worth catching: from here on the two
  are editing different documents, and everything after it is a consequence.
  """
  def compare(session, op, room_document, room_revision) do
    debug = Map.get(op, :debug)
    room = digest(room_document)

    cond do
      is_nil(debug) or is_nil(Map.get(debug, :digest)) ->
        :unknown

      Map.get(debug, :digest) == room ->
        Logger.info(
          "[collab] agree " <>
            fields([
              {"session", session},
              {"rev", room_revision},
              {"len", String.length(room_document)},
              {"digest", room}
            ])
        )

        :match

      true ->
        Logger.warning(
          "[collab] MISMATCH " <>
            fields([
              {"session", session},
              {"rev", room_revision},
              {"room_len", String.length(room_document)},
              {"room_digest", room},
              {"editor_len", Map.get(debug, :length)},
              {"editor_digest", Map.get(debug, :digest)},
              {"editor_visible_len", Map.get(debug, :visible_length)},
              {"caret", Map.get(debug, :caret)},
              {"pending", Map.get(debug, :pending)}
            ])
        )

        :mismatch
    end
  end

  @doc """
  Say exactly where two documents part company, with the text either side.

  Called once the editor has sent the text it holds, which is the only way to
  turn "these differ" into a character position.
  """
  def divergence(session, editor_markdown, room_document) do
    index = first_difference(editor_markdown, room_document)

    Logger.warning(
      "[collab] DIVERGED-AT " <>
        fields([
          {"session", session},
          {"index", index},
          {"room", inspect(window(room_document, index))},
          {"editor", inspect(window(editor_markdown, index))}
        ])
    )

    index
  end

  def caret(session, offset, debug) do
    Logger.info(
      "[collab] caret " <>
        fields([
          {"session", session},
          {"offset", offset},
          {"editor_len", debug && Map.get(debug, :length)},
          {"visible_len", debug && Map.get(debug, :visible_length)},
          {"digest", debug && Map.get(debug, :digest)},
          {"rev", debug && Map.get(debug, :revision)}
        ])
    )
  end

  def note(message, pairs), do: Logger.info("[collab] #{message} " <> fields(pairs))

  @doc """
  Two sessions holding the same document but not the same coordinates.

  This is the state that misplaces a caret, and it is invisible to a
  comparison of the documents: both are correct markdown, of the same length,
  with the same fingerprint. They differ only in how many characters each
  editor believes the text has — so an offset one of them sends means a
  different place in the other, and typing after a full stop lands before it.
  """
  def misaligned(session, other, mine, theirs) do
    Logger.warning(
      "[collab] MISALIGNED " <>
        fields([
          {"session", session},
          {"other", other},
          {"document", Map.get(mine, :digest)},
          {"len", Map.get(mine, :visible_length)},
          {"other_len", Map.get(theirs, :visible_length)},
          {"coords", Map.get(mine, :visible_digest)},
          {"other_coords", Map.get(theirs, :visible_digest)}
        ])
    )
  end

  @doc """
  Where two sessions' coordinates part company, with the text either side.

  The index is into the rendered text, which is what offsets are measured in,
  so it names the character an edit would be misplaced around.
  """
  def coordinate_gap(session, other, mine, theirs) do
    index = first_difference(mine, theirs)

    Logger.warning(
      "[collab] COORDS-DIFFER-AT " <>
        fields([
          {"session", session},
          {"other", other},
          {"index", index},
          {"this", inspect(window(mine, index))},
          {"other", inspect(window(theirs, index))}
        ])
    )

    index
  end

  # The first code point at which the two texts differ, or the length of the
  # shorter one when one is a prefix of the other.
  def first_difference(a, b) do
    a = String.graphemes(a)
    b = String.graphemes(b)

    Enum.zip(a, b)
    |> Enum.find_index(fn {x, y} -> x != y end)
    |> case do
      nil -> min(length(a), length(b))
      index -> index
    end
  end

  defp window(text, index) do
    from = max(index - 20, 0)

    text
    |> String.slice(from, 44)
    |> String.replace("\n", "\\n")
  end

  defp rendered(nil), do: "none"

  defp rendered(%{at: at, remove: remove, insert: insert}),
    do: "#{at}/#{remove}/#{inspect(insert)}"

  defp outcome(%{applied: true, revision: revision}), do: "applied@#{revision}"
  defp outcome(%{applied: false}), do: "REFUSED"
  defp outcome(_), do: "?"

  defp fields(pairs) do
    pairs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{value}" end)
  end
end
