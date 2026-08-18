defmodule SprintLensWeb.SessionLiveTest do
  @moduledoc """
  The live board (SCR-05, SCR-06, SCR-07).

  The realtime tests mount two LiveViews at once — a facilitator and a
  participant — because "every participant's view MUST follow in realtime"
  (FR-206) is a claim about two clients, and a single-client test cannot
  make it.
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Retro
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer

  setup :register_and_log_in_user

  setup %{user: user} do
    team = team_with_lead(user)
    participant = insert(:user, language: "en")
    join_team(participant, team)

    %{
      team: team,
      facilitator: user,
      participant: participant,
      participant_conn: log_in_user(build_conn(), participant)
    }
  end

  defp create_session(ctx, attrs \\ %{}) do
    {:ok, session} =
      Retro.create_session(ctx.facilitator, ctx.team, Map.merge(%{title: "R"}, attrs))

    session
  end

  defp start_session(ctx, attrs \\ %{}) do
    {:ok, session} = Retro.start_session(ctx.facilitator, create_session(ctx, attrs))
    on_exit(fn -> SessionServer.stop(session.id) end)
    session
  end

  describe "SCR-05 and SCR-06 — the session list" do
    @tag req: ["FR-201"]
    test "a member creates a session from a template", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      {:ok, _lv, html} =
        lv
        |> form("#session_form", session: %{title: "Sprint 12"})
        |> render_submit()
        |> follow_redirect(ctx.conn)

      assert html =~ "Sprint 12"
      assert [session] = Retro.list_sessions(ctx.team)
      assert session.title == "Sprint 12"
    end

    @tag req: ["FR-210"]
    test "the anonymous and blind modes are chosen here, before anyone writes", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      lv
      |> form("#session_form",
        session: %{title: "Safe", is_anonymous: "true", is_blind: "true"}
      )
      |> render_submit()

      assert [session] = Retro.list_sessions(ctx.team)
      assert session.is_anonymous
      assert session.is_blind
    end

    @tag req: ["FR-203"]
    test "lists upcoming and past sessions with their state", ctx do
      _running = start_session(ctx)

      {:ok, _lv, html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert html =~ "Running"
    end

    @tag req: ["FR-917"]
    test "has a designed empty state", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert has_element?(lv, "#sessions-empty")
    end

    @tag req: ["FR-919"]
    test "an invalid vote budget is reported rather than saved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      html =
        lv
        |> form("#session_form", session: %{title: "Bad", vote_budget: "0"})
        |> render_submit()

      assert html =~ "input-error"
      assert Retro.list_sessions(ctx.team) == []
    end

    @tag req: ["FR-919"]
    test "validates as you type", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert lv |> form("#session_form", session: %{title: ""}) |> render_change() =~
               "input-error"
    end

    @tag req: ["FR-106"]
    test "an archived team offers no form", ctx do
      archived = team_with_lead(ctx.facilitator, %{is_archived: true})

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{archived}/sessions")

      refute has_element?(lv, "#session_form")
    end

    @tag req: ["FR-203"]
    test "a scheduled, anonymous and a closed session all read clearly in the list", ctx do
      at = DateTime.utc_now(:second) |> DateTime.add(1, :day)
      create_session(ctx, %{title: "Later", scheduled_at: at, is_anonymous: true})
      {:ok, _closed} = Retro.close_session(ctx.facilitator, start_session(ctx, %{title: "Done"}))

      {:ok, _lv, html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert html =~ "Not started"
      assert html =~ "Closed"
      assert html =~ "Anonymous"
      assert html =~ "Scheduled for"
    end

    @tag req: ["NFR-201"]
    test "a member firing create against an archived team is refused", ctx do
      archived = team_with_lead(ctx.facilitator, %{is_archived: true})
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{archived}/sessions")

      assert render_submit(lv, "save", %{"session" => %{"title" => "Sneaky"}}) =~
               "do not have permission"

      assert Retro.list_sessions(archived) == []
    end

    @tag req: ["FR-103"]
    test "a forged template id from another team is refused", ctx do
      other_lead = insert(:user)
      other_team = team_with_lead(other_lead)

      {:ok, theirs} =
        SprintLens.Teams.create_template(other_lead, other_team, %{
          name: "Theirs",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert render_submit(lv, "save", %{
               "session" => %{"title" => "Borrowed", "template_id" => to_string(theirs.id)}
             }) =~ "does not exist"
    end

    @tag req: ["FR-103"]
    test "another team's sessions are not reachable", ctx do
      theirs = team_with_lead(insert(:user))

      assert {:error, {:live_redirect, %{to: "/teams"}}} =
               live(ctx.conn, ~p"/teams/#{theirs}/sessions")
    end
  end

  describe "SCR-07 — the board" do
    @tag req: ["FR-205"]
    test "the facilitator starts the session", ctx do
      session = create_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      lv |> element("#start-session") |> render_click()

      {:ok, reloaded} = Retro.fetch_session(ctx.facilitator, session.id)
      assert Session.state(reloaded) == :active
    end

    @tag req: ["FR-201"]
    test "shows the columns the session was created with", ctx do
      session = start_session(ctx)

      {:ok, _lv, html} = live(ctx.conn, ~p"/sessions/#{session}")

      assert html =~ "Went well"
      assert html =~ "To improve"
    end

    @tag req: ["FR-204"]
    test "shows the join code so it can be read out", ctx do
      session = start_session(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      assert lv |> element("#join-code") |> render() =~ session.join_code
    end

    @tag req: ["NFR-201"]
    test "a participant gets no facilitator controls", ctx do
      session = start_session(ctx)

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{session}")

      refute has_element?(lv, "#advance-phase")
      refute has_element?(lv, "#close-session")
      refute has_element?(lv, "#pause-timer")
    end

    @tag req: ["FR-103"]
    test "someone outside the team cannot open the board", ctx do
      session = start_session(ctx)
      outsider_conn = log_in_user(build_conn(), insert(:user))

      assert {:error, {:live_redirect, %{to: "/home"}}} =
               live(outsider_conn, ~p"/sessions/#{session}")
    end
  end

  describe "phases in realtime (FR-206)" do
    setup ctx do
      Map.put(ctx, :session, start_session(ctx))
    end

    @tag req: ["FR-206", "NFR-102"]
    test "the participant's view follows the facilitator's change", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert participant_lv |> element("#phase-bar") |> render() =~ "Check-in"

      facilitator_lv |> element("#advance-phase") |> render_click()

      assert render(participant_lv) =~ ~s(aria-current="true")
      assert participant_lv |> element("[aria-current='true']") |> render() =~ "Brainstorm"
    end

    @tag req: ["FR-206"]
    test "the facilitator reverts, and everyone follows back", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      facilitator_lv |> element("#advance-phase") |> render_click()
      facilitator_lv |> element("#revert-phase") |> render_click()

      assert participant_lv |> element("[aria-current='true']") |> render() =~ "Check-in"
    end

    @tag req: ["FR-206"]
    test "the facilitator skips straight to a later phase", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#phase-vote") |> render_click()

      {:ok, reloaded} = Retro.fetch_session(ctx.facilitator, ctx.session.id)
      assert Session.phase(reloaded) == :vote
    end

    @tag req: ["FR-206"]
    test "reverting from the first phase says so rather than doing nothing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert lv |> element("#revert-phase") |> render_click() =~ "not available in this phase"
    end

    @tag req: ["NFR-201"]
    test "a participant firing the phase event is refused", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render_click(lv, "advance_phase", %{}) =~ "do not have permission"

      {:ok, reloaded} = Retro.fetch_session(ctx.facilitator, ctx.session.id)
      assert Session.phase(reloaded) == :checkin
    end

    @tag req: ["FR-915"]
    test "the phase region is announced to assistive technology", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert lv |> element("#phase-bar") |> render() =~ ~s(aria-live="polite")
    end
  end

  describe "the timer in realtime (FR-208)" do
    setup ctx do
      Map.put(ctx, :session, start_session(ctx))
    end

    @tag req: ["FR-208"]
    test "everyone sees the countdown the facilitator started", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert participant_lv |> element("#timer-remaining") |> render() =~ "—"

      facilitator_lv |> element("#timer-300") |> render_click()

      assert participant_lv |> element("#timer-remaining") |> render() =~ "5:00"
    end

    @tag req: ["FR-208"]
    test "pausing and resetting reach everyone too", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      facilitator_lv |> element("#timer-60") |> render_click()
      facilitator_lv |> element("#pause-timer") |> render_click()
      assert participant_lv |> element("#timer-remaining") |> render() =~ "1:00"

      facilitator_lv |> element("#reset-timer") |> render_click()
      assert participant_lv |> element("#timer-remaining") |> render() =~ "—"
    end

    @tag req: ["FR-915"]
    test "the timer is a live region, so expiry can be announced", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert lv |> element("#timer") |> render() =~ ~s(aria-live="polite")
    end

    @tag req: ["NFR-201"]
    test "a participant firing a timer event is refused", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render_click(lv, "start_timer", %{"seconds" => "300"}) =~ "do not have permission"
    end
  end

  describe "presence and readiness (FR-213, FR-307)" do
    setup ctx do
      Map.put(ctx, :session, start_session(ctx))
    end

    @tag req: ["FR-307"]
    test "the board shows who is in the session", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, _participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render(facilitator_lv) =~ ctx.participant.display_name
      assert has_element?(facilitator_lv, "#participant-#{ctx.participant.id}")
    end

    @tag req: ["FR-213"]
    test "marking yourself ready updates the count the facilitator sees", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert facilitator_lv |> element("#ready-count") |> render() =~ "0 of 2"

      participant_lv |> element("#toggle-ready") |> render_click()

      assert facilitator_lv |> element("#ready-count") |> render() =~ "1 of 2"
    end

    @tag req: ["FR-213"]
    test "readiness can be taken back", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#toggle-ready") |> render_click()
      assert lv |> element("#ready-count") |> render() =~ "1 of 1"

      lv |> element("#toggle-ready") |> render_click()
      assert lv |> element("#ready-count") |> render() =~ "0 of 1"
    end

    @tag req: ["FR-207"]
    test "the facilitator hands the role over, and both views follow", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      facilitator_lv
      |> element("#hand-over-#{ctx.participant.id}")
      |> render_click()

      # The new facilitator gains the controls; the old one loses them.
      assert has_element?(participant_lv, "#advance-phase")
      refute has_element?(facilitator_lv, "#advance-phase")
    end
  end

  describe "closing (FR-205, FR-215)" do
    @tag req: ["FR-205"]
    test "closing tells everyone and makes the board read-only", ctx do
      session = start_session(ctx)
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{session}")

      facilitator_lv |> element("#close-session") |> render_click()

      assert render(participant_lv) =~ "Closed"
      refute has_element?(facilitator_lv, "#advance-phase")
      refute has_element?(participant_lv, "#toggle-ready")
    end
  end

  describe "joining by code (FR-204)" do
    @tag req: ["FR-204"]
    test "a member joins with the code the facilitator read out", ctx do
      session = start_session(ctx)
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/join")

      {:ok, _lv, html} =
        lv
        |> form("#join_form", join: %{code: String.downcase(session.join_code)})
        |> render_submit()
        |> follow_redirect(ctx.participant_conn, ~p"/sessions/#{session}")

      assert html =~ session.title
    end

    @tag req: ["FR-204"]
    test "the short link joins straight away", ctx do
      session = start_session(ctx)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(ctx.participant_conn, ~p"/join/#{session.join_code}")

      assert to == "/sessions/#{session.id}"
    end

    @tag req: ["FR-204"]
    test "an unknown code says so without confirming which codes exist", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/join")

      assert lv |> form("#join_form", join: %{code: "ZZZZZZ"}) |> render_submit() =~
               "No session with that code"
    end

    @tag req: ["FR-205"]
    test "a closed session says it is closed", ctx do
      session = start_session(ctx)
      {:ok, closed} = Retro.close_session(ctx.facilitator, session)

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/join")

      assert lv |> form("#join_form", join: %{code: closed.join_code}) |> render_submit() =~
               "session is closed"
    end

    @tag req: ["FR-204"]
    test "someone else's code is not found", ctx do
      other_lead = insert(:user)
      other_team = team_with_lead(other_lead)
      {:ok, theirs} = Retro.create_session(other_lead, other_team, %{title: "Theirs"})

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/join")

      assert lv |> form("#join_form", join: %{code: theirs.join_code}) |> render_submit() =~
               "No session with that code"
    end
  end

  describe "the board's modes and refusals" do
    @tag req: ["FR-209", "FR-210"]
    test "an anonymous, blind session says so on the board", ctx do
      session = start_session(ctx, %{is_anonymous: true, is_blind: true})

      {:ok, _lv, html} = live(ctx.conn, ~p"/sessions/#{session}")

      assert html =~ "Anonymous"
      assert html =~ "Cards hidden until revealed"
    end

    @tag req: ["FR-205"]
    test "starting a session that has already started says so", ctx do
      session = start_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      assert render_click(lv, "start", %{}) =~ "not available right now"
    end

    @tag req: ["FR-207"]
    test "handing the role to someone who is not in the team is refused", ctx do
      session = start_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      assert render_click(lv, "transfer_facilitator", %{
               "user-id" => to_string(insert(:user).id)
             }) =~ "does not exist"
    end

    @tag req: ["FR-208"]
    test "an out-of-range timer duration is reported, not applied", ctx do
      session = start_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      assert render_click(lv, "start_timer", %{"seconds" => "1"}) =~ "need attention"
    end

    @tag req: ["FR-306"]
    test "an event the board does not act on leaves it alone", ctx do
      session = start_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      # Card events belong to the board milestone; until then they must not
      # disturb the frame.
      Events.broadcast(session.id, "card.created", %{})

      assert render(lv) =~ session.title
    end

    @tag req: ["FR-205"]
    test "a session deleted underneath an open board leaves it standing", ctx do
      session = start_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      SprintLens.Repo.delete!(SprintLens.Repo.get(Session, session.id))
      Events.broadcast(session.id, "phase.changed", %{})

      assert render(lv) =~ session.title
    end
  end

  describe "reconnecting (FR-309)" do
    @tag req: ["FR-309", "NFR-401"]
    test "a fresh mount rebuilds the board from a snapshot, not from replayed events", ctx do
      session = start_session(ctx)
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")

      facilitator_lv |> element("#phase-vote") |> render_click()
      facilitator_lv |> element("#timer-600") |> render_click()

      # A participant arriving now missed both events entirely.
      {:ok, late_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{session}")

      assert late_lv |> element("[aria-current='true']") |> render() =~ "Vote"
      assert late_lv |> element("#timer-remaining") |> render() =~ "10:00"
    end
  end
end
