defmodule SprintLens.Retro.EventsTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Retro.Events

  describe "events/0" do
    @tag req: ["FR-306"]
    test "are exactly the ones section 7.3 lists" do
      assert Enum.sort(Events.events()) ==
               Enum.sort(~w(
                 phase.changed
                 timer.updated
                 card.created
                 card.updated
                 card.deleted
                 card.moved
                 group.created
                 group.updated
                 group.deleted
                 vote.updated
                 vote.revealed
                 focus.changed
                 note.updated
                 presence.updated
                 mood.updated
                 action.created
                 action.updated
                 session.closed
               ))
    end
  end

  describe "topic/1" do
    @tag req: ["FR-306"]
    test "is one topic per session, which is what keeps order per session" do
      assert Events.topic(1) != Events.topic(2)
      assert Events.topic(42) =~ "42"
    end
  end

  describe "broadcast/3" do
    @tag req: ["FR-306", "NFR-102"]
    test "reaches a subscriber" do
      session_id = System.unique_integer([:positive])
      Events.subscribe(session_id)

      Events.broadcast(session_id, "phase.changed", %{phase: :vote})

      assert_receive {:retro_event, "phase.changed", %{phase: :vote}}
    end

    @tag req: ["FR-306"]
    test "does not reach a different session" do
      mine = System.unique_integer([:positive])
      theirs = System.unique_integer([:positive])
      Events.subscribe(mine)

      Events.broadcast(theirs, "phase.changed", %{})

      refute_receive {:retro_event, _event, _payload}, 50
    end

    @tag req: ["FR-306"]
    test "stops reaching a process that has unsubscribed" do
      session_id = System.unique_integer([:positive])
      Events.subscribe(session_id)
      Events.unsubscribe(session_id)

      Events.broadcast(session_id, "phase.changed", %{})

      refute_receive {:retro_event, _event, _payload}, 50
    end

    @tag req: ["FR-306"]
    test "refuses an event name the spec does not define" do
      # A typo in an event name is otherwise a message nobody receives and
      # nobody notices.
      assert_raise ArgumentError, ~r/section 7.3/, fn ->
        Events.broadcast(1, "card.exploded", %{})
      end
    end

    @tag req: ["NFR-503"]
    test "is measured, so the two-second budget can be observed" do
      handler = "events-test-#{System.unique_integer([:positive])}"
      test = self()

      :telemetry.attach(
        handler,
        [:sprint_lens, :realtime, :broadcast, :stop],
        fn _event, measurements, metadata, _config ->
          send(test, {:measured, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      Events.broadcast(System.unique_integer([:positive]), "card.created", %{})

      assert_receive {:measured, %{duration: duration}, %{event: "card.created"}}
      assert duration >= 0
    end
  end
end
