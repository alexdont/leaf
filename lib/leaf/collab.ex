defmodule Leaf.Collab do
  @moduledoc """
  Live editing, wired into a LiveView in one call.

  Everything a shared document needs — placing edits that crossed on the wire,
  agreeing which version everyone is on, putting a session back in step after
  its socket drops, showing where other people's carets are — is here rather
  than in the host. It is not obvious code and it is not code worth writing
  twice; every part of it exists because something went visibly wrong without
  it.

  ## Using it

      def mount(%{"id" => id}, _session, socket) do
        {:ok,
         Leaf.Collab.join(socket,
           room: MyApp.Notes.room(id),
           editor_id: "note-editor",
           identity: %{name: socket.assigns.current_user.name}
         )}
      end

  and in the template:

      <.leaf_editor
        id="note-editor"
        content={@leaf_collab.content}
        collaboration={@leaf_collab.collaboration}
      />

  That is the whole integration. `join/2` attaches a `handle_info` hook, so the
  host writes no message handling of its own and its own `handle_info` clauses
  are left alone.

  ## What the host still owns

  Starting a room per document and supervising it — Leaf has no opinion about
  how many nodes you run or how you name processes. And saying where documents
  live, which is `Leaf.Collab.Store`.

  ## Turning it off

  Not calling `join/2` costs nothing. The editor does no collaboration work
  unless it is asked to: no coordinates measured, no fingerprints taken, no
  selection listener attached. Somebody using Leaf for a comment box pays for
  none of this.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, send_update: 2]

  alias Leaf.Collab.Log
  alias Leaf.Collab.Room

  @doc """
  Join the document this room holds.

  Options:

    * `:room` — the room process, started and supervised by the host
    * `:editor_id` — the `id` given to `leaf_editor`
    * `:identity` — `%{name:, color:}`, both optional. A host with signed-in
      users passes theirs so everyone sees a name rather than an identifier.
    * `:awareness` — show other people's carets and selections. Defaults true.
    * `:debug` — diagnostics. Defaults false; see `Leaf.Collab.Log`.
  """
  def join(socket, opts) do
    room = Keyword.fetch!(opts, :room)
    editor_id = Keyword.fetch!(opts, :editor_id)
    session_id = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

    info = Room.info(room)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(info.pubsub, info.topic)
      Room.join(room, session_id, self(), Keyword.get(opts, :identity, %{}))
    end

    snapshot = Room.snapshot(room)

    socket
    |> assign(:leaf_collab, %{
      room: room,
      editor_id: editor_id,
      session_id: session_id,
      topic: info.topic,
      pubsub: info.pubsub,
      debug: Keyword.get(opts, :debug, false),
      content: snapshot.document,
      revision: snapshot.revision,
      people: Room.cursors(room, session_id),
      # Recent edits, newest first, for a host that wants to show activity.
      # Kept short: it is a feed, not a history.
      activity: [],
      reconcile: false,
      collaboration: %{
        operations: true,
        awareness: Keyword.get(opts, :awareness, true),
        debug: Keyword.get(opts, :debug, false),
        revision: snapshot.revision
      }
    })
    |> attach_hook(:leaf_collab, :handle_info, &handle_message/2)
  end

  @doc "Everyone in the document, for a host that wants to list them."
  def people(socket), do: socket.assigns.leaf_collab.people

  # --------------------------------------------------------------------------
  # Messages
  # --------------------------------------------------------------------------

  defp handle_message({:leaf_operation, op}, socket) do
    %{room: room, session_id: session} = state = socket.assigns.leaf_collab
    result = Room.apply_operation(room, session, op)
    if state.debug, do: Log.operation(session, op, result)

    case result do
      %{applied: false} ->
        if state.debug, do: Log.note("refused", session: session, reason: "cannot be placed")

        # Settled even though it did not land: an edit the editor is still
        # counting is an edit every later one is placed against.
        ack(state, Map.get(op, :seq), Room.snapshot(room).revision)

        # Its next snapshot is taken as the truth. Pushing our copy at it
        # instead would be re-derived, disagree again, and refuse the next
        # keystroke too — a loop in which nothing typed survives.
        {:halt, put(socket, %{reconcile: true, diverged: true})}

      result ->
        broadcast(state, {:leaf_collab_changed, result})
        ack(state, Map.get(op, :seq), result.revision)

        if state.debug and
             Log.compare(session, op, result.document, result.revision) == :mismatch do
          send_update(Leaf, id: state.editor_id, action: :debug_snapshot)
        end

        push_cursors(state)

        {:halt,
         put(socket, %{
           content: result.document,
           revision: result.revision,
           people: Room.cursors(room, session),
           activity: note_activity(state, result, :you)
         })}
    end
  end

  # Somebody else's edit. Handed to the editor to apply without moving this
  # reader's caret.
  defp handle_message({:leaf_collab_changed, result}, socket) do
    state = socket.assigns.leaf_collab

    send_update(Leaf,
      id: state.editor_id,
      action: :apply_operation,
      content: result.document,
      op: %{
        at: result.entry.at,
        remove: result.entry.remove,
        insert: result.entry.insert,
        rendered: result.entry.rendered,
        revision: result.revision
      }
    )

    push_cursors(state)

    {:halt,
     put(socket, %{
       content: result.document,
       revision: result.revision,
       activity: note_activity(state, result, :peer)
     })}
  end

  defp handle_message({:leaf_collab_adopted, result}, socket) do
    {:halt, adopt_locally(socket, result)}
  end

  defp handle_message({:leaf_awareness, %{offset: offset, focused: focused} = info}, socket) do
    state = socket.assigns.leaf_collab

    if state.debug do
      if focused, do: Log.caret(state.session_id, offset, Map.get(info, :debug))
      check_alignment(state, Map.get(info, :debug))
    end

    # `focused && offset` would store false on a blur, which is not nil and so
    # would keep drawing the caret of somebody who has left.
    Room.put_cursor(
      state.room,
      state.session_id,
      if(focused, do: offset),
      if(focused, do: Map.get(info, :anchor))
    )

    broadcast(state, :leaf_collab_cursors)

    {:halt, socket}
  end

  defp handle_message(:leaf_collab_cursors, socket) do
    state = socket.assigns.leaf_collab
    push_cursors(state)
    {:halt, put(socket, %{people: Room.cursors(state.room, state.session_id)})}
  end

  # On load, and again whenever the socket comes back. Either side may have
  # moved while they were apart.
  defp handle_message({:leaf_ready, %{markdown: markdown, revision: revision}}, socket) do
    state = socket.assigns.leaf_collab
    snapshot = Room.snapshot(state.room)

    cond do
      markdown == snapshot.document ->
        {:halt, socket}

      # The room went past what this editor last heard, so the room is newer.
      # Not knowing a version is not a claim to be ahead of one.
      snapshot.revision > ((is_integer(revision) && revision) || 0) ->
        {:halt, resync(socket, snapshot)}

      # This editor is holding writing the room never saw — quite possibly the
      # only copy of it.
      true ->
        result = Room.adopt(state.room, state.session_id, markdown)
        broadcast(state, {:leaf_collab_adopted, result})
        ack(state, nil, result.revision)
        {:halt, put(socket, %{content: markdown, revision: result.revision, diverged: false})}
    end
  end

  defp handle_message({:leaf_resync, _}, socket) do
    {:halt, resync(socket, Room.snapshot(socket.assigns.leaf_collab.room))}
  end

  # The snapshot the editor sends on its own. Taken as the truth when an edit
  # of its could not be placed; it carries everything typed since.
  defp handle_message({:leaf_changed, %{markdown: markdown}}, socket) do
    state = socket.assigns.leaf_collab

    if state.reconcile do
      result = Room.adopt(state.room, state.session_id, markdown)
      broadcast(state, {:leaf_collab_adopted, result})
      ack(state, nil, result.revision)

      {:halt,
       put(socket, %{
         reconcile: false,
         diverged: false,
         content: markdown,
         revision: result.revision
       })}
    else
      {:halt, put(socket, %{content: markdown})}
    end
  end

  defp handle_message({:leaf_debug_state, report}, socket) do
    state = socket.assigns.leaf_collab

    if state.debug do
      Room.report(state.room, state.session_id, report)

      Log.divergence(
        state.session_id,
        Map.get(report, :markdown) || "",
        Room.snapshot(state.room).document
      )

      compare_coordinates(state, report)
    end

    {:halt, socket}
  end

  defp handle_message(_message, socket), do: {:cont, socket}

  # --------------------------------------------------------------------------

  @activity_limit 40

  defp note_activity(state, %{entry: entry}, whose) when is_map(entry) do
    who = if whose == :you, do: "you", else: entry.session

    Enum.take(
      [%{who: who, mine: whose == :you, what: describe(entry)} | state.activity],
      @activity_limit
    )
  end

  defp note_activity(state, _result, _whose), do: state.activity

  defp describe(%{at: at, remove: 0, insert: insert}), do: "insert #{inspect(insert)} at #{at}"
  defp describe(%{at: at, remove: remove, insert: ""}), do: "delete #{remove} at #{at}"

  defp describe(%{at: at, remove: remove, insert: insert}),
    do: "replace #{remove} at #{at} with #{inspect(insert)}"

  defp put(socket, changes) do
    assign(socket, :leaf_collab, Map.merge(socket.assigns.leaf_collab, changes))
  end

  defp broadcast(state, message) do
    # broadcast_from: we have already acted on it here, and PubSub delivers to
    # every subscriber including the sender.
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), state.topic, message)
  end

  defp ack(state, seq, revision) do
    send_update(Leaf, id: state.editor_id, action: :revision, revision: revision, seq: seq)
  end

  defp push_cursors(state) do
    send_update(Leaf,
      id: state.editor_id,
      action: :peer_cursors,
      cursors: Room.cursors(state.room, state.session_id)
    )
  end

  # Replaces the document while keeping the writer's caret, which set_content
  # would drop at the top of the page.
  defp resync(socket, snapshot) do
    state = socket.assigns.leaf_collab

    send_update(Leaf,
      id: state.editor_id,
      action: :apply_operation,
      content: snapshot.document,
      op: %{
        at: 0,
        remove: 0,
        insert: "",
        rendered: nil,
        resync: true,
        revision: snapshot.revision
      }
    )

    put(socket, %{content: snapshot.document, revision: snapshot.revision, diverged: false})
  end

  defp adopt_locally(socket, result) do
    state = socket.assigns.leaf_collab
    ack(state, nil, result.revision)

    send_update(Leaf,
      id: state.editor_id,
      action: :set_content,
      content: result.document,
      mark_saved: false
    )

    put(socket, %{content: result.document, revision: result.revision, diverged: false})
  end

  # Two sessions can hold the same document and still disagree about how many
  # characters are in it. That is what misplaces a caret, and neither session
  # can see it alone.
  defp check_alignment(_state, nil), do: :ok

  defp check_alignment(state, report) do
    Room.report(state.room, state.session_id, report)

    Room.reports(state.room)
    |> Enum.reject(fn {id, _} -> id == state.session_id end)
    |> Enum.find(fn {_id, other} ->
      Map.get(other, :digest) == Map.get(report, :digest) and
        Map.get(other, :visible_digest) != Map.get(report, :visible_digest)
    end)
    |> case do
      nil ->
        :ok

      {other_id, other} ->
        Log.misaligned(state.session_id, other_id, report, other)
        send_update(Leaf, id: state.editor_id, action: :debug_snapshot)
    end
  end

  defp compare_coordinates(state, report) do
    Room.reports(state.room)
    |> Enum.reject(fn {id, other} ->
      id == state.session_id or is_nil(Map.get(other, :visible))
    end)
    |> Enum.find(fn {_id, other} -> Map.get(other, :visible) != Map.get(report, :visible) end)
    |> case do
      nil ->
        :ok

      {other_id, other} ->
        Log.coordinate_gap(
          state.session_id,
          other_id,
          Map.get(report, :visible) || "",
          Map.get(other, :visible) || ""
        )
    end
  end
end
