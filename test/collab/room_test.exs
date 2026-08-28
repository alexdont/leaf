defmodule Leaf.Collab.RoomTest do
  @moduledoc """
  Two people typing at once.

  Each describes their edit against the text as they saw it, which is not the
  text the other one's edit produced. Applying both verbatim puts characters in
  different places for each of them, and the documents come apart by exactly
  the length of what the other person typed — one tab reading
  "or hot ye s this?" while the other reads "or hot ye st his?".
  """
  use ExUnit.Case, async: false

  alias Leaf.Collab.Room

  # Long enough for the offsets these tests use to be inside it.
  @content String.duplicate("abcdefghijklmnopqrstuvwxyz0123456789 ", 6)

  # A document of its own per test: a room is one per document now, so tests
  # that share one would be sharing a document.
  setup do
    name = :"room-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Room, name: name, pubsub: Leaf.TestPubSub, document_id: "t", initial_content: @content},
      id: name
    )

    %{room: name}
  end

  defp op(at, remove, insert, revision) do
    %{at: at, remove: remove, insert: insert, revision: revision, base_length: nil}
  end

  describe "rebase/2" do
    test "an edit before ours moves everything we point at" do
      assert %{at: 14} = Room.rebase(op(10, 0, "x", 0), op(0, 0, "abcd", 0))
    end

    test "an edit after ours leaves us alone" do
      assert %{at: 10} = Room.rebase(op(10, 0, "x", 0), op(50, 0, "abcd", 0))
    end

    test "a deletion before ours pulls us back" do
      assert %{at: 6} = Room.rebase(op(10, 0, "x", 0), op(0, 4, "", 0))
    end

    test "an edit ending exactly where ours starts still moves us" do
      assert %{at: 12} = Room.rebase(op(10, 0, "x", 0), op(8, 2, "abcd", 0))
    end

    test "overlapping edits keep only what the other one did not touch" do
      # We remove 10..20; someone else already removed 12..18.
      rebased = Room.rebase(op(10, 10, "", 0), op(12, 6, "", 0))

      assert rebased.at == 10
      assert rebased.remove == 4, "2 before their cut, 2 after it"
    end
  end

  # Verified by hand with three tabs; pinned here so it stays true. Two sessions
  # exercise rebasing over one other edit, which is the easy case — the third
  # is what makes an edit rebase over a rebase.
  describe "reset" do
    # The revision is how every session decides who is behind, and that only
    # works while it never goes backwards. A reset to zero left live sessions
    # holding a higher number than the room, so the next reconciliation
    # decided the room was stale and adopted the pre-reset text right back.
    test "moves the revision forward, never back", %{room: room} do
      Room.apply_operation(room, "A", op(0, 0, "x", 0))
      Room.apply_operation(room, "A", op(1, 0, "y", 1))
      before_reset = Room.snapshot(room).revision

      result = Room.reset(room)

      assert result.revision > before_reset,
             "a session holding the old revision must read as behind, not ahead"

      assert result.document == @content
    end

    test "replies with what a caller needs to broadcast", %{room: room} do
      result = Room.reset(room)

      # The shape {:leaf_collab_adopted, …} expects: without both of these the
      # other sessions cannot be moved onto the reset document.
      assert is_binary(result.document)
      assert is_integer(result.revision)
    end

    test "a session on the old revision is behind after a reset", %{room: room} do
      Room.apply_operation(room, "A", op(0, 0, "x", 0))
      old_revision = Room.snapshot(room).revision

      %{revision: new_revision} = Room.reset(room)

      assert new_revision > old_revision,
             "leaf_ready from a pre-reset session must resolve to the room winning"
    end
  end

  describe "three people typing at once" do
    test "every edit lands where its author meant it to", %{room: room} do
      # None of them has seen the others: all three were written against the
      # document as it was.
      Room.apply_operation(room, "A", op(0, 0, "A", 0))
      Room.apply_operation(room, "B", op(10, 0, "B", 0))
      Room.apply_operation(room, "C", op(20, 0, "C", 0))

      document = Room.snapshot(room).document

      assert String.at(document, 0) == "A"
      assert String.at(document, 11) == "B", "moved past A's character, and only A's"
      assert String.at(document, 22) == "C", "moved past both"

      # And each still sits beside the character it was written next to, which
      # is the thing that actually matters to whoever typed it.
      assert String.at(document, 12) == String.at(@content, 10)
      assert String.at(document, 23) == String.at(@content, 20)
    end

    test "the order they arrive in changes nothing", %{room: room} do
      Room.apply_operation(room, "A", op(0, 0, "A", 0))
      Room.apply_operation(room, "B", op(10, 0, "B", 0))
      Room.apply_operation(room, "C", op(20, 0, "C", 0))
      one = Room.snapshot(room).document

      Room.reset(room)

      Room.apply_operation(room, "C", op(20, 0, "C", 0))
      Room.apply_operation(room, "A", op(0, 0, "A", 0))
      Room.apply_operation(room, "B", op(10, 0, "B", 0))
      two = Room.snapshot(room).document

      assert one == two, "everyone must end up reading the same document"
    end

    test "nobody's edit is refused for being late", %{room: room} do
      results =
        for {session, at} <- [{"A", 5}, {"B", 15}, {"C", 25}, {"D", 35}] do
          Room.apply_operation(room, session, op(at, 0, session, 0))
        end

      assert Enum.all?(results, & &1.applied),
             "an edit written before seeing the others is crossed, not stale"
    end

    test "a deletion by one does not misplace the others", %{room: room} do
      Room.apply_operation(room, "A", op(0, 5, "", 0))
      Room.apply_operation(room, "B", op(20, 0, "B", 0))
      Room.apply_operation(room, "C", op(30, 0, "C", 0))

      document = Room.snapshot(room).document

      # B and C were written against offsets five characters further along.
      assert String.at(document, 15) == "B"
      assert String.at(document, 26) == "C"
    end
  end

  describe "two people typing at once" do
    test "both edits land where their authors meant them to", %{room: room} do
      base = Room.snapshot(room)
      assert base.revision == 0

      # Both write against revision 0. A types near the start, B near the end.
      a = Room.apply_operation(room, "A", op(0, 1, "@", 0))
      assert a.applied
      assert a.revision == 1

      b = Room.apply_operation(room, "B", op(100, 0, "!", 0))
      assert b.applied

      document = Room.snapshot(room).document

      assert String.starts_with?(document, "@"), "A's edit is where A put it"

      # B meant to insert at 100 in the document B could see. A's edit did not
      # change the length, so it stays at 100 — the interesting part is that it
      # was rebased rather than refused.
      assert String.at(document, 100) == "!"
    end

    test "an insertion by one shifts where the other's lands", %{room: room} do
      Room.apply_operation(room, "A", op(0, 0, "12345", 0))

      # B wrote this against revision 0, before A's five characters existed.
      Room.apply_operation(room, "B", op(10, 0, "|", 0))

      document = Room.snapshot(room).document
      original = @content

      # B's mark must still sit next to the character it was next to, now five
      # places later — not five characters away from it.
      assert String.at(document, 15) == "|"
      assert String.at(document, 16) == String.at(original, 10)
    end

    test "the room stays one document no matter which order they arrive in", %{room: room} do
      Room.reset(room)
      Room.apply_operation(room, "A", op(0, 0, "aaa", 0))
      Room.apply_operation(room, "B", op(20, 0, "bbb", 0))
      one = Room.snapshot(room).document

      Room.reset(room)
      Room.apply_operation(room, "B", op(20, 0, "bbb", 0))
      Room.apply_operation(room, "A", op(0, 0, "aaa", 0))
      two = Room.snapshot(room).document

      assert one == two, "arrival order must not change what everybody ends up reading"
    end

    # The markdown splice is what the room stores; the rendered splice is what
    # a peer uses to put the characters on screen. Rebasing one and not the
    # other places the text at an offset nobody meant: an "o" typed as the
    # second character of "how" arrived at the far end of the line, leaving
    # "hw about thiso".
    test "the rendered splice is rebased too, not just the markdown one", %{room: room} do
      Room.apply_operation(room, "A", %{
        at: 0,
        remove: 0,
        insert: "aaa",
        rendered: %{at: 0, remove: 0, insert: "aaa"},
        revision: 0,
        base_length: nil
      })

      result =
        Room.apply_operation(room, "B", %{
          at: 10,
          remove: 0,
          insert: "X",
          rendered: %{at: 10, remove: 0, insert: "X"},
          revision: 0,
          base_length: nil
        })

      assert result.entry.at == 13, "the markdown splice moves past A's three characters"

      assert result.entry.rendered.at == 13,
             "and so must the splice the peer actually draws with"
    end

    # A rendered splice can only be rebased over other rendered splices. When
    # one is missing there is nothing to rebase over, and a wrong offset is
    # worse than a slower path: dropping it tells the peer to use the server's
    # HTML, which is always right.
    test "a rendered splice is dropped rather than guessed at", %{room: room} do
      Room.apply_operation(room, "A", %{
        at: 0,
        remove: 0,
        insert: "aaa",
        rendered: nil,
        revision: 0,
        base_length: nil
      })

      result =
        Room.apply_operation(room, "B", %{
          at: 10,
          remove: 0,
          insert: "X",
          rendered: %{at: 10, remove: 0, insert: "X"},
          revision: 0,
          base_length: nil
        })

      assert result.entry.at == 13, "the markdown splice still rebases"
      assert result.entry.rendered == nil, "but the peer must fall back to the html"
    end

    test "an uncrossed operation keeps its rendered splice", %{room: room} do
      result =
        Room.apply_operation(room, "A", %{
          at: 4,
          remove: 0,
          insert: "X",
          rendered: %{at: 2, remove: 0, insert: "X"},
          revision: 0,
          base_length: nil
        })

      assert result.entry.rendered == %{at: 2, remove: 0, insert: "X"},
             "with nothing to rebase over it must be passed through untouched"
    end

    # An editor's own edits are already accounted for in its next one: it typed
    # the second character into a document that contains the first, whether or
    # not the acknowledgement has come back yet. Rebasing over them shifts the
    # edit past text it already knows about — far enough that it points outside
    # the document and is refused, which is what filled the log with REFUSED
    # while "I like turtles" was being typed.
    test "an editor's own earlier edit is not counted against its next one", %{room: room} do
      Room.apply_operation(room, "A", %{
        at: 0,
        remove: 0,
        insert: "12",
        rendered: %{at: 0, remove: 0, insert: "12"},
        revision: 0,
        base_length: nil
      })

      # Typed before the acknowledgement arrived, so it still says revision 0 —
      # but its offset already counts the "12" this same editor just wrote.
      result =
        Room.apply_operation(room, "A", %{
          at: 2,
          remove: 0,
          insert: "X",
          rendered: %{at: 2, remove: 0, insert: "X"},
          revision: 0,
          base_length: nil
        })

      assert result.applied, "a writer's own next keystroke must not be refused"
      assert result.entry.at == 2, "and must not be shifted past their own typing"
      assert String.starts_with?(Room.snapshot(room).document, "12X")
    end

    test "someone else's edit is still counted", %{room: room} do
      Room.apply_operation(room, "A", %{
        at: 0,
        remove: 0,
        insert: "12",
        rendered: %{at: 0, remove: 0, insert: "12"},
        revision: 0,
        base_length: nil
      })

      result =
        Room.apply_operation(room, "B", %{
          at: 2,
          remove: 0,
          insert: "X",
          rendered: %{at: 2, remove: 0, insert: "X"},
          revision: 0,
          base_length: nil
        })

      assert result.entry.at == 4, "B never saw A's two characters, so B's edit moves past them"
    end

    test "an edit written against the current revision is untouched", %{room: room} do
      Room.apply_operation(room, "A", op(0, 0, "aaa", 0))

      # B has seen A's edit, so B's offsets already account for it.
      Room.apply_operation(room, "B", op(0, 0, "B", 1))

      assert String.starts_with?(Room.snapshot(room).document, "Baaa")
    end
  end
end
