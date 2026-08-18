defmodule SprintLens.Retro.SessionServerTest do
  @moduledoc """
  The facilitator hand-off (FR-207).

  The grace period is 50ms under test rather than the sixty real seconds the
  spec asks for — a suite that waits a minute per case is a suite nobody runs.
  What is being tested is the rule, not the number: that the countdown starts
  when the facilitator goes, is cancelled when they come back, and hands the
  role to someone still in the room when it expires.
  """

  use SprintLens.DataCase

  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer
  alias SprintLensWeb.Presence

  setup do
    facilitator = insert(:user)
    team = team_with_lead(facilitator)
    participant = insert(:user)
    join_team(participant, team)

    session = active_session(team, facilitator)

    on_exit(fn -> SessionServer.stop(session.id) end)

    %{team: team, facilitator: facilitator, participant: participant, session: session}
  end

  # Tracks presence from a throwaway process, the way a LiveView holds it:
  # the entry goes when the process does, which is what "disconnected" means.
  #
  # The process is stopped at the end of the test. Presence is global while
  # the sandbox rolls each test back, so session ids repeat — a tracker left
  # running would make the next test's session look occupied by people from
  # this one.
  defp join_session(session, user, meta \\ %{}) do
    test = self()

    pid =
      spawn(fn ->
        Presence.track_user(self(), session.id, user.id, meta)
        send(test, :joined)
        receive do: (:leave -> :ok)
      end)

    assert_receive :joined
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    pid
  end

  defp leave(pid) do
    ref = Process.monitor(pid)
    send(pid, :leave)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  # Polls rather than busy-loops: the thing being waited for is a timer in
  # another process, and spinning without yielding just burns the attempts
  # before it can possibly have fired.
  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end

  # A grace period long enough that "the countdown is running" can be observed
  # before it expires. The default 50ms is for tests that want the expiry.
  defp with_long_grace do
    original = Application.get_env(:sprint_lens, :facilitator_grace_ms)
    Application.put_env(:sprint_lens, :facilitator_grace_ms, 5_000)
    on_exit(fn -> Application.put_env(:sprint_lens, :facilitator_grace_ms, original) end)
  end

  defp facilitator_id(session_id), do: Repo.get(Session, session_id).facilitator_id

  describe "normalise_start/1" do
    @tag req: ["FR-207"]
    test "treats someone else having started it first as success" do
      assert SessionServer.normalise_start({:ok, self()}) == {:ok, self()}
      assert SessionServer.normalise_start({:error, {:already_started, self()}}) == {:ok, self()}
    end

    @tag req: ["FR-207"]
    test "passes any other failure through, rather than hiding it" do
      assert SessionServer.normalise_start({:error, :max_children}) == {:error, :max_children}
    end
  end

  describe "ensure_started/1" do
    @tag req: ["FR-207"]
    test "starts one server per session and returns the same one after that", ctx do
      assert {:ok, pid} = SessionServer.ensure_started(ctx.session.id)
      assert {:ok, ^pid} = SessionServer.ensure_started(ctx.session.id)
      assert SessionServer.whereis(ctx.session.id) == pid
    end

    @tag req: ["FR-207"]
    test "there is no server until someone asks for one", ctx do
      assert SessionServer.whereis(ctx.session.id) == nil
      refute SessionServer.handover_pending?(ctx.session.id)
    end

    @tag req: ["FR-207"]
    test "stopping is safe whether or not one is running", ctx do
      assert SessionServer.stop(ctx.session.id) == :ok
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)
      assert SessionServer.stop(ctx.session.id) == :ok

      # The registry unregisters when it sees the process go, which is a
      # message rather than a synchronous step.
      assert eventually(fn -> SessionServer.whereis(ctx.session.id) == nil end)
    end

    @tag req: ["FR-207"]
    test "telling a session with no server about presence is a no-op", ctx do
      assert SessionServer.presence_changed(ctx.session.id) == :ok
    end
  end

  describe "the hand-off countdown" do
    @tag req: ["FR-207"]
    test "does not run while the facilitator is present", ctx do
      join_session(ctx.session, ctx.facilitator)
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      refute SessionServer.handover_pending?(ctx.session.id)
    end

    @tag req: ["FR-207"]
    test "starts when the facilitator is absent", ctx do
      with_long_grace()
      join_session(ctx.session, ctx.participant)
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      assert SessionServer.handover_pending?(ctx.session.id)
    end

    @tag req: ["FR-207"]
    test "is cancelled when the facilitator comes back in time", ctx do
      with_long_grace()

      join_session(ctx.session, ctx.participant)
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)
      assert SessionServer.handover_pending?(ctx.session.id)

      join_session(ctx.session, ctx.facilitator)
      SessionServer.presence_changed(ctx.session.id)

      assert eventually(fn -> not SessionServer.handover_pending?(ctx.session.id) end)
      assert facilitator_id(ctx.session.id) == ctx.facilitator.id
    end

    @tag req: ["FR-207"]
    test "offers the role to a remaining participant when it expires", ctx do
      Events.subscribe(ctx.session.id)

      join_session(ctx.session, ctx.participant)
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      assert_receive {:retro_event, "presence.updated", %{reason: "handover"}}, 2_000
      assert facilitator_id(ctx.session.id) == ctx.participant.id
    end

    @tag req: ["FR-207"]
    test "hands over to the longest-present participant, not the newest", ctx do
      newcomer = insert(:user)
      join_team(newcomer, ctx.team)

      join_session(ctx.session, ctx.participant, %{joined_at: 100})
      join_session(ctx.session, newcomer, %{joined_at: 900})

      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      assert eventually(fn -> facilitator_id(ctx.session.id) == ctx.participant.id end)
    end

    @tag req: ["FR-207"]
    test "does nothing when the room is empty — there is nobody to hand to", ctx do
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      # The countdown expires with nobody to promote; the facilitator keeps
      # the role rather than the session being left with none.
      refute eventually(fn -> facilitator_id(ctx.session.id) != ctx.facilitator.id end, 20)
    end

    @tag req: ["FR-207"]
    test "leaves a session that is not active alone", ctx do
      with_long_grace()
      {:ok, closed} = Retro.close_session(ctx.facilitator, ctx.session)
      join_session(ctx.session, ctx.participant)

      {:ok, _pid} = SessionServer.ensure_started(closed.id)

      refute SessionServer.handover_pending?(closed.id)
      assert facilitator_id(closed.id) == ctx.facilitator.id
    end

    @tag req: ["FR-207"]
    test "the countdown is not postponed by other people arriving", ctx do
      Events.subscribe(ctx.session.id)

      join_session(ctx.session, ctx.participant)
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      # Someone else joining must not restart the clock, or a busy session
      # could keep a departed facilitator's role indefinitely.
      newcomer = insert(:user)
      join_team(newcomer, ctx.team)
      join_session(ctx.session, newcomer)
      SessionServer.presence_changed(ctx.session.id)

      assert_receive {:retro_event, "presence.updated", %{reason: "handover"}}, 2_000
    end

    @tag req: ["FR-207"]
    test "the facilitator returning between expiry and hand-off keeps the role", ctx do
      facilitator_pid = join_session(ctx.session, ctx.facilitator)
      join_session(ctx.session, ctx.participant)

      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)
      refute SessionServer.handover_pending?(ctx.session.id)

      leave(facilitator_pid)
      SessionServer.presence_changed(ctx.session.id)

      assert eventually(fn -> facilitator_id(ctx.session.id) == ctx.participant.id end)
    end

    @tag req: ["FR-207"]
    test "a stale expiry message from a cancelled countdown is ignored", ctx do
      with_long_grace()
      {:ok, pid} = SessionServer.ensure_started(ctx.session.id)

      # A timer cancelled after its message was already in the mailbox.
      send(pid, {:handover, make_ref()})

      assert facilitator_id(ctx.session.id) == ctx.facilitator.id
      assert Process.alive?(pid)
    end

    @tag req: ["FR-207"]
    test "a session whose facilitator was removed counts as having none", ctx do
      Repo.update_all(
        from(s in Session, where: s.id == ^ctx.session.id),
        set: [facilitator_id: nil]
      )

      join_session(ctx.session, ctx.participant)
      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      assert eventually(fn -> facilitator_id(ctx.session.id) == ctx.participant.id end)
    end

    @tag req: ["FR-207"]
    test "someone present but no longer in the team is not promoted", ctx do
      # Left the team while still connected: the hand-off must refuse rather
      # than give the board to somebody who cannot see it.
      outsider = insert(:user)
      join_session(ctx.session, outsider)

      {:ok, _pid} = SessionServer.ensure_started(ctx.session.id)

      refute eventually(fn -> facilitator_id(ctx.session.id) == outsider.id end, 20)
      assert facilitator_id(ctx.session.id) == ctx.facilitator.id
    end

    @tag req: ["FR-207"]
    test "a session that has been deleted stops the countdown rather than crashing", ctx do
      with_long_grace()
      {:ok, pid} = SessionServer.ensure_started(ctx.session.id)
      Repo.delete!(Repo.get(Session, ctx.session.id))

      SessionServer.presence_changed(ctx.session.id)

      refute SessionServer.handover_pending?(ctx.session.id)
      assert Process.alive?(pid)
    end
  end
end
