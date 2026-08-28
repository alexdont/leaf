defmodule Leaf.Collab.LogTest do
  @moduledoc """
  The log is a diagnostic instrument, so it has to be trustworthy: a
  fingerprint that does not match the editor's would report disagreement where
  there is none, and a first-difference that is off by one would send the next
  investigation to the wrong character.
  """
  # Not async: the routine lines are :info and the suite runs at :warning, so
  # the level has to be lowered for the duration and put back afterwards.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Leaf.Collab.Log

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  describe "digest/1" do
    # Verified against the editor's _digest for the same inputs. If these ever
    # part company the log becomes actively misleading, so they are pinned.
    test "matches the editor, byte for byte" do
      assert Log.digest("") == "811c9dc5"
      assert Log.digest("a") == "e40c292c"
      assert Log.digest("hello world") == "d58b3fa7"
      assert Log.digest("a\nb\n") == "7a256dee"
    end

    test "a single changed character changes it" do
      refute Log.digest("hello world") == Log.digest("hello xorld")
    end

    test "text of the same length in a different order changes it" do
      refute Log.digest("ab") == Log.digest("ba")
    end
  end

  describe "first_difference/2" do
    test "identical text has no difference before its end" do
      assert Log.first_difference("abc", "abc") == 3
    end

    test "finds the character that parted company" do
      assert Log.first_difference("hello world", "hello xorld") == 6
    end

    test "a prefix differs at the point it stops" do
      assert Log.first_difference("abc", "abcdef") == 3
    end

    test "counts characters, not bytes" do
      assert Log.first_difference("héllo", "héxlo") == 2
    end
  end

  describe "compare/4" do
    test "says nothing useful when the editor sent no fingerprint" do
      assert Log.compare("s", %{}, "text", 1) == :unknown
    end

    test "agreement is recorded, not just disagreement" do
      op = %{debug: %{digest: Log.digest("text"), length: 4}}

      log = capture_log(fn -> assert Log.compare("s1", op, "text", 3) == :match end)

      assert log =~ "[collab] agree"
      assert log =~ "session=s1"
    end

    test "a disagreement is loud and carries both sides" do
      op = %{debug: %{digest: "deadbeef", length: 99, caret: 12, pending: 2}}

      log = capture_log(fn -> assert Log.compare("s2", op, "text", 4) == :mismatch end)

      assert log =~ "[collab] MISMATCH"
      assert log =~ "editor_digest=deadbeef"
      assert log =~ "room_digest=#{Log.digest("text")}"
      assert log =~ "caret=12"
      assert log =~ "pending=2"
    end
  end

  test "divergence/3 names the character and shows both neighbourhoods" do
    room = "the quick brown fox jumps over the lazy dog"
    editor = "the quick brown fix jumps over the lazy dog"

    log = capture_log(fn -> assert Log.divergence("s3", editor, room) == 17 end)

    assert log =~ "[collab] DIVERGED-AT"
    assert log =~ "index=17"
    assert log =~ "brown fox"
    assert log =~ "brown fix"
  end

  test "operation/3 records what was asked for and what became of it" do
    op = %{
      seq: 4,
      revision: 2,
      at: 10,
      remove: 1,
      insert: "x",
      rendered: %{at: 8, remove: 1, insert: "x"},
      base_length: 100,
      debug: %{caret: 11, pending: 1}
    }

    log = capture_log(fn -> Log.operation("s4", op, %{applied: true, revision: 3}) end)

    assert log =~ "[collab] op"
    assert log =~ "seq=4"
    assert log =~ "at=10"
    assert log =~ ~s(rendered=8/1/"x")
    assert log =~ "base_len=100"
    assert log =~ "caret=11"
    assert log =~ "outcome=applied@3"
  end

  test "a refused operation says so" do
    log =
      capture_log(fn ->
        Log.operation("s5", %{at: 0, remove: 0, insert: ""}, %{applied: false})
      end)

    assert log =~ "outcome=REFUSED"
  end
end
