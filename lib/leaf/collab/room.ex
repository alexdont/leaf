defmodule Leaf.Collab.Room do
  @moduledoc """
  The shared document behind the Leaf collaboration testbed.

  This exists because the first version of the testbed kept the operation log
  in each LiveView's own assigns, which quietly made the page unable to show
  the thing it was built to show. A LiveView is torn down whenever its socket
  drops — routine on this host, where the socket often falls back to longpoll
  and a backgrounded tab stops polling — and it remounts with empty assigns.
  So a tab left open while you typed in another one came back blank, having
  missed every broadcast it was not alive for.

  Holding the document and the operation log in one process fixes that and is
  also honest about what real collaboration needs: a session that joins late,
  or rejoins after a drop, has to be able to catch up. A page that only ever
  works for sessions present since the first keystroke is not collaborating.

  Still no CRDT, on purpose. Operations are applied in arrival order and
  `base_length` mismatches are recorded rather than resolved — surfacing
  divergence is the point, since that is what a real merge layer would have to
  handle.
  """
  use GenServer

  require Logger

  @log_limit 40

  # How far back an edit may be rebased from. An editor further behind than
  # this has been out of touch long enough that reconciling it wholesale is
  # more honest than replaying it forward.
  @history_limit 200

  # Long enough that a burst of typing is one write, short enough that a crash
  # costs a sentence rather than a session.
  @flush_after 2_000

  # Someone who types without pausing would otherwise never trigger a flush at
  # all, so the wait is capped.
  @flush_at_most_every 15_000

  # Enough to tell people apart at a glance without a colour picker.
  @palette ~w(#e11d48 #2563eb #16a34a #d97706 #9333ea #0891b2)

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      %{
        store: Keyword.get(opts, :store, Leaf.Collab.Store.None),
        document_id: Keyword.get(opts, :document_id, "document"),
        # Where sessions hear about each other. One topic per document.
        topic:
          Keyword.get(opts, :topic, "leaf:collab:" <> Keyword.get(opts, :document_id, "document")),
        pubsub: Keyword.fetch!(opts, :pubsub),
        # What an empty document contains before anybody types. The store wins
        # if it has anything.
        initial_content: Keyword.get(opts, :initial_content, ""),
        # Tunable because what counts as "the writing has paused" depends on
        # where it is being written to, and because a test should be able to
        # watch the timers work rather than sleep through them.
        flush_after: Keyword.get(opts, :flush_after, @flush_after),
        flush_at_most_every: Keyword.get(opts, :flush_at_most_every, @flush_at_most_every)
      },
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  @doc """
  The current document and recent operations, for a session that just mounted.
  """
  def snapshot(room), do: GenServer.call(room, :snapshot)

  @doc """
  Apply one session's operation to the shared document.

  An operation built against a document of a different length than the room
  holds is REJECTED rather than applied. Its offsets refer to text that is not
  here, so applying it would put characters in the wrong places for everybody,
  and no later edit would undo that. The reply says `applied: false` and
  carries the room's document so the sender can be put back in step.
  """
  def apply_operation(room, session_id, op) do
    GenServer.call(room, {:apply, session_id, op})
  end

  @doc """
  Register a session so its caret can be shown to everyone else.

  `identity` is who the host says this is: `%{name: "Sasha", color: "#e11d48"}`.
  Both are optional and both have fallbacks, because a host may have no idea
  who is editing — a public page, a draft nobody has signed in for — and that
  should still work. A host with real users passes their names, and everyone
  else sees a name rather than a random identifier.

  The room monitors `pid`, so a session that closes its tab — or drops its
  socket, which happens routinely on longpoll — has its caret removed without
  needing to say goodbye. A LiveView cannot be relied on to run cleanup on the
  way out, so being told is not an option.
  """
  # One optional argument, not two. Defaulting `room` as well would make
  # `join(session_id, pid, identity)` bind the session id to `room` and call a
  # process by that name — a trap this fell into twice.
  def join(room, session_id, pid, identity \\ %{}),
    do: GenServer.call(room, {:join, session_id, pid, identity})

  @doc """
  Move a session's caret and selection.

  `offset` is the caret and `anchor` is where the selection began; equal means
  nothing is selected. `nil` means the person is no longer in the editor.
  """
  def put_cursor(room, session_id, offset, anchor \\ nil) do
    GenServer.call(room, {:put_cursor, session_id, offset, anchor})
  end

  @doc """
  Record what a session says it is holding.

  Kept so two sessions can be compared: holding the same document while
  disagreeing about how many characters are in it is exactly the state that
  misplaces a caret, and neither session can see it on its own.
  """
  def report(room, session_id, info), do: GenServer.call(room, {:report, session_id, info})

  @doc "Every session's last report."
  def reports(room), do: GenServer.call(room, :reports)

  @doc "Everyone's caret except `except`, ready to hand to Leaf."
  # One optional argument, not two: with both `room` and `except` defaulted,
  # `cursors(session_id)` binds the session id to `room` and tries to call a
  # process by that name.
  def cursors(room, except \\ nil), do: GenServer.call(room, {:cursors, except})

  @doc """
  Replace the document with a session's own copy of it.

  Used when an operation could not be placed. The editor's serialization is the
  canonical form — markdown round-tripped through HTML comes back normalized,
  so a room holding hand-written markdown (`-   ]` rather than `- ]`) can never
  agree with an editor about lengths. Taking the editor's text ends that
  disagreement in the only direction that converges; pushing the room's text
  back at the editor does not, because the editor immediately re-normalizes it
  and disagrees again.
  """
  def adopt(room, session_id, markdown),
    do: GenServer.call(room, {:adopt, session_id, markdown})

  @doc "Clear the document and the log, for everyone."
  def reset(room), do: GenServer.call(room, :reset)

  @doc """
  Where this room's sessions hear about each other.

  Asked of the room rather than repeated by the host: one place decides, and a
  host that gets it wrong would have sessions that never see each other with
  nothing obviously broken.
  """
  def info(room), do: GenServer.call(room, :info)

  @doc "Write the document out now, without waiting for the timers."
  def flush_now(room), do: GenServer.call(room, :flush_now)

  @impl true
  def init(%{store: store, document_id: document_id} = opts) do
    # Flushing on the way down is the whole reason a room can be stopped
    # gracefully rather than killed.
    Process.flag(:trap_exit, true)

    state =
      fresh()
      |> Map.merge(%{
        store: store,
        document_id: document_id,
        topic: opts.topic,
        pubsub: opts.pubsub,
        document: opts.initial_content,
        # Kept, not just used: a reset puts the document back to it, and
        # without this the room would reset to nothing.
        initial_content: opts.initial_content,
        flush_after: Map.get(opts, :flush_after, @flush_after),
        flush_at_most_every: Map.get(opts, :flush_at_most_every, @flush_at_most_every),
        dirty: false,
        deadline: nil
      })
      |> hydrate()

    {:ok, state}
  end

  # Whatever the store has is the document. Nothing there is not a failure: it
  # is a note nobody has written yet.
  defp hydrate(state) do
    case state.store.load(state.document_id) do
      {:ok, %{document: document} = loaded} ->
        %{state | document: document, revision: Map.get(loaded, :revision, 0)}

      _ ->
        state
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       document: state.document,
       ops: state.ops,
       diverged: state.diverged,
       revision: state.revision
     }, state}
  end

  def handle_call({:apply, session_id, op}, _from, state) do
    concurrent = concurrent_since(state, Map.get(op, :revision), session_id)
    rebased = rebase_over(op, concurrent)

    # Two separate questions, and conflating them was a mistake worth not
    # repeating. Does this edit describe a document we recognize — judged only
    # when nothing crossed it on the wire, since crossing legitimately changes
    # the length. And can the result actually be placed in the text we hold.
    recognized? = concurrent != [] or not diverged?(state.document, op)
    placeable? = placeable?(state.document, rebased)

    if recognized? and placeable? do
      apply_op(state, session_id, rebased)
    else
      {:reply, %{applied: false, document: state.document, entry: nil, diverged: true},
       %{state | diverged: true}}
    end
  end

  def handle_call({:adopt, session_id, markdown}, _from, state) do
    entry = %{
      session: session_id,
      at: 0,
      remove: String.length(state.document),
      insert: markdown,
      rendered: nil,
      adopted: true
    }

    revision = state.revision + 1

    state = %{
      state
      | document: markdown,
        ops: Enum.take([entry | state.ops], @log_limit),
        diverged: false,
        revision: revision,
        # Nothing before a wholesale replacement can be rebased over it.
        history: []
    }

    {:reply, %{document: state.document, ops: state.ops, entry: entry, revision: revision},
     changed(state)}
  end

  def handle_call(:reset, _from, state) do
    # People stay: resetting the document is not the same as everyone leaving,
    # and dropping them would strand monitors we still hold.
    fresh_state = %{
      fresh()
      | document: state.initial_content,
        people: state.people,
        store: state.store,
        document_id: state.document_id,
        topic: state.topic,
        pubsub: state.pubsub,
        initial_content: state.initial_content,
        flush_after: state.flush_after,
        flush_at_most_every: state.flush_at_most_every
    }

    {:reply, %{document: fresh_state.document, ops: fresh_state.ops, diverged: false},
     fresh_state}
  end

  def handle_call({:join, session_id, pid, identity}, _from, state) do
    Process.monitor(pid)

    person = %{
      session: session_id,
      pid: pid,
      offset: nil,
      anchor: nil,
      # What the host calls this person, falling back to the session id. A
      # short identifier is a poor name but it is better than nothing, and it
      # keeps the room working for a host with no idea who is editing.
      name: Map.get(identity, :name) || session_id,
      color:
        Map.get(identity, :color) ||
          Enum.at(@palette, map_size(state.people) |> rem(length(@palette)))
    }

    {:reply, :ok, %{state | people: Map.put(state.people, session_id, person)}}
  end

  def handle_call({:put_cursor, session_id, offset, anchor}, _from, state) do
    people =
      case Map.fetch(state.people, session_id) do
        {:ok, person} ->
          Map.put(state.people, session_id, %{person | offset: offset, anchor: anchor || offset})

        :error ->
          state.people
      end

    {:reply, :ok, %{state | people: people}}
  end

  def handle_call(:info, _from, state) do
    {:reply, %{topic: state.topic, pubsub: state.pubsub, document_id: state.document_id}, state}
  end

  def handle_call(:flush_now, _from, state) do
    {:reply, :ok, flush(state)}
  end

  def handle_call({:report, session_id, info}, _from, state) do
    reports = Map.put(Map.get(state, :reports, %{}), session_id, info)
    {:reply, :ok, Map.put(state, :reports, reports)}
  end

  def handle_call(:reports, _from, state) do
    {:reply, Map.get(state, :reports, %{}), state}
  end

  def handle_call({:cursors, except}, _from, state) do
    cursors =
      state.people
      |> Map.values()
      |> Enum.reject(&(&1.session == except or is_nil(&1.offset)))
      |> Enum.map(
        &%{
          id: &1.session,
          label: &1.name,
          color: &1.color,
          offset: &1.offset,
          anchor: &1.anchor || &1.offset
        }
      )
      |> Enum.sort_by(& &1.id)

    {:reply, cursors, state}
  end

  @impl true
  def handle_info(:flush, state), do: {:noreply, flush(%{state | timer: nil})}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    gone =
      state.people
      |> Enum.filter(fn {_id, p} -> p.pid == pid end)
      |> Enum.map(fn {id, _} -> id end)

    people = Map.drop(state.people, gone)
    reports = Map.drop(Map.get(state, :reports, %{}), gone)

    {:noreply, %{state | people: people, reports: reports}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Called for a graceful stop, and for a supervisor shutdown, because the room
  # traps exits. Whatever has not been written yet is written now: this is the
  # last moment anything can be.
  @impl true
  def terminate(_reason, state) do
    flush(state)
    :ok
  end

  # The document moved. Tell the cheap store straight away — it exists so a
  # crash costs seconds — and arrange for the expensive one to be written when
  # the typing stops, or sooner if it has been going on a while.
  defp changed(state) do
    attempt(state, :save, fn -> state.store.save(state.document_id, snapshot_for_store(state)) end)

    state
    |> Map.put(:dirty, true)
    |> schedule_flush()
  end

  defp schedule_flush(state) do
    now = System.monotonic_time(:millisecond)
    # Set once per run of changes: the point past which waiting for a pause has
    # gone on long enough.
    deadline = state.deadline || now + state.flush_at_most_every
    at = min(now + state.flush_after, deadline)

    if state.timer, do: Process.cancel_timer(state.timer)

    %{
      state
      | deadline: deadline,
        timer: Process.send_after(self(), :flush, max(at - now, 0))
    }
  end

  defp flush(%{dirty: false} = state), do: state

  defp flush(state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    result =
      attempt(state, :flush, fn ->
        state.store.flush(state.document_id, snapshot_for_store(state))
      end)

    case result do
      :ok ->
        %{state | dirty: false, deadline: nil, timer: nil, conflict: false}

      {:error, :conflict} ->
        # Somebody edited the document outside this session. Both copies are
        # somebody's work, and this one is not more entitled to exist, so it
        # stays in memory and stops trying to overwrite theirs.
        %{state | deadline: nil, timer: nil, conflict: true}

      {:error, _reason} ->
        # Left dirty on purpose: the next change will try again.
        %{state | deadline: nil, timer: nil}
    end
  end

  defp snapshot_for_store(state), do: %{document: state.document, revision: state.revision}

  # A store is somebody else's code talking to somebody else's disk or database,
  # and it can be unavailable at exactly the moment it is needed. It must not
  # take the room with it: the document is still in memory, people are still
  # editing, and a later attempt may well succeed. Losing the room would lose
  # the writing outright, which is the one outcome worth avoiding.
  defp attempt(state, what, fun) do
    fun.()
  rescue
    error ->
      Logger.warning(
        "[collab] store #{what} failed for #{state.document_id}: #{Exception.message(error)}"
      )

      {:error, error}
  catch
    kind, reason ->
      Logger.warning(
        "[collab] store #{what} #{kind} for #{state.document_id}: #{inspect(reason)}"
      )

      {:error, reason}
  end

  # Trailing newline trimmed on purpose. The editor's document is derived from
  # its DOM, and that round-trip does not reproduce a trailing newline — so a
  # room holding one is a character longer than every client, and every single
  # operation reports a base_length mismatch. The warning was firing constantly
  # while nothing was actually wrong.
  # Everything applied after the revision this operation was written against,
  # by somebody else.
  #
  # An editor's own edits are excluded, and the omission of that was expensive.
  # A writer types the second character into a document that already contains
  # the first, whether or not the acknowledgement has come back yet — so the
  # offsets already account for it. Rebasing over their own typing pushes each
  # keystroke further past text it already knew about until it points beyond
  # the end of the document and is refused.
  defp concurrent_since(_state, nil, _session), do: []

  defp concurrent_since(state, revision, session) do
    Enum.filter(state.history, &(&1.revision > revision and &1.session != session))
  end

  # An operation carries the same edit twice: in markdown offsets, which is what
  # the room stores, and in the rendered offsets a peer uses to put the
  # characters on screen. Both have to be rebased, each over the other
  # operations' version of itself. Moving only the markdown one placed the text
  # at an offset nobody meant — an "o" typed as the second character of "how"
  # arriving at the far end of the line, leaving "hw about thiso".
  defp rebase_over(op, concurrent) do
    op
    |> rebase_markdown(concurrent)
    |> Map.put(:rendered, rebase_rendered(Map.get(op, :rendered), concurrent))
  end

  defp rebase_markdown(op, concurrent) do
    Enum.reduce(concurrent, op, fn earlier, carried -> rebase(carried, earlier.splice) end)
  end

  # Nil means "no rendered form", which a peer reads as "use the server's HTML".
  # If any operation in between lacked one there is nothing to rebase over, and
  # guessing would be worse than the slower, always-correct path.
  defp rebase_rendered(nil, _concurrent), do: nil

  defp rebase_rendered(rendered, concurrent) do
    if Enum.any?(concurrent, &is_nil(&1.rendered)) do
      nil
    else
      Enum.reduce(concurrent, rendered, fn earlier, carried ->
        rebase(carried, earlier.rendered)
      end)
    end
  end

  defp apply_op(state, session_id, op) do
    document = splice(state.document, op)

    entry = %{
      session: session_id,
      at: op.at,
      remove: op.remove,
      insert: op.insert,
      # Passed straight through to the peers: it is the sender's description of
      # its own edit on screen, and only the sender can produce it.
      rendered: Map.get(op, :rendered)
    }

    revision = state.revision + 1

    state = %{
      state
      | document: document,
        ops: Enum.take([entry | state.ops], @log_limit),
        revision: revision,
        history:
          Enum.take(
            state.history ++
              [
                %{
                  revision: revision,
                  session: session_id,
                  splice: op,
                  rendered: Map.get(op, :rendered)
                }
              ],
            @history_limit
          )
    }

    {:reply,
     %{
       applied: true,
       document: document,
       entry: entry,
       diverged: state.diverged,
       revision: revision
     }, changed(state)}
  end

  defp fresh do
    %{
      document: "",
      ops: [],
      diverged: false,
      people: %{},
      # Every applied splice, newest last, so an edit built against an older
      # version of the document can be rebased onto the current one.
      revision: 0,
      history: [],
      reports: %{},
      # Replaced from the options in init/1; here so a reset can carry them
      # through without the room forgetting where its document lives.
      store: Leaf.Collab.Store.None,
      document_id: "document",
      topic: nil,
      pubsub: nil,
      initial_content: "",
      flush_after: @flush_after,
      flush_at_most_every: @flush_at_most_every,
      dirty: false,
      deadline: nil,
      timer: nil,
      conflict: false
    }
  end

  @doc """
  Rebase `op` so it means the same thing after `applied` has happened.

  Two people typing at once each describe their edit against the text as they
  saw it, which is not the text the other one's edit produced. Applying both
  verbatim puts the characters in different places for each of them — the
  documents come apart by exactly the length of what the other person typed.

  The disjoint cases are exact. Overlapping edits — two people changing the
  same characters — have no answer that preserves both intentions, so what is
  kept is whatever each edit touched that the other did not, which at least
  leaves every session with the same text.
  """
  def rebase(op, applied) do
    applied_end = applied.at + applied.remove
    shift = String.length(applied.insert) - applied.remove

    cond do
      # Entirely before us: everything we point at has moved.
      applied_end <= op.at ->
        %{op | at: op.at + shift}

      # Entirely after us: nothing we point at has moved.
      op.at + op.remove <= applied.at ->
        op

      true ->
        op_end = op.at + op.remove
        before = max(applied.at - op.at, 0)
        rest = max(op_end - applied_end, 0)

        %{op | at: min(op.at, applied.at), remove: before + rest}
    end
  end

  # Apply one splice, and report whether the document we hold was the length the
  # editor thought it was applying to. A mismatch means the two have diverged —
  # the case `base_length` exists to make visible.
  # Compared against the trimmed length too: markdown that ends in a blank line
  # survives a round trip through the DOM without it, so a difference confined
  # to trailing whitespace is a representation detail rather than two sessions
  # disagreeing about the text.
  defp diverged?(text, op) do
    length = String.length(text)
    op[:base_length] not in [nil, length, String.length(String.trim_trailing(text))]
  end

  # Rebasing can only do so much: overlapping edits, or an editor further behind
  # than the history reaches, can produce a splice that points outside the text.
  # Applying it anyway would scatter characters, so it is refused and the
  # session settled up from the room's copy instead.
  defp placeable?(text, %{at: at, remove: remove}) do
    at >= 0 and remove >= 0 and at + remove <= String.length(text)
  end

  defp placeable?(_text, _op), do: false

  defp splice(text, %{at: at, remove: remove, insert: insert}) do
    length = String.length(text)

    String.slice(text, 0, at) <>
      insert <> String.slice(text, at + remove, max(length - at - remove, 0))
  end
end
