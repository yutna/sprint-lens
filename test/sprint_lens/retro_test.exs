defmodule SprintLens.RetroTest do
  use SprintLens.DataCase

  alias SprintLens.Accounts.Scope
  alias SprintLens.Retro
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Teams

  setup do
    facilitator = insert(:user)
    team = team_with_lead(facilitator)
    participant = insert(:user)
    join_team(participant, team)

    %{team: team, facilitator: facilitator, participant: participant}
  end

  describe "create_session/3" do
    @tag req: ["FR-201"]
    test "any team member can start one from a built-in template", ctx do
      template = Enum.find(Teams.list_builtin_templates(), &(&1.name == "Start-Stop-Continue"))

      assert {:ok, session} =
               Retro.create_session(ctx.participant, ctx.team, %{
                 title: "Sprint 12",
                 template_id: template.id
               })

      assert session.title == "Sprint 12"
      assert Enum.map(session.columns, & &1.name) == ["Start", "Stop", "Continue"]
    end

    @tag req: ["FR-201"]
    test "the columns are copied, so editing the template later cannot rewrite them", ctx do
      {:ok, template} =
        Teams.create_template(ctx.facilitator, ctx.team, %{
          name: "Ours",
          columns: [%{"name" => "Before"}, %{"name" => "Also before"}]
        })

      {:ok, session} =
        Retro.create_session(ctx.facilitator, ctx.team, %{title: "R", template_id: template.id})

      {:ok, _renamed} =
        Teams.update_template(ctx.facilitator, ctx.team, template, %{
          name: "Ours",
          columns: [%{"name" => "After"}, %{"name" => "Also after"}]
        })

      {:ok, reloaded} = Retro.fetch_session(ctx.facilitator, session.id)
      assert Enum.map(reloaded.columns, & &1.name) == ["Before", "Also before"]
    end

    @tag req: ["FR-207"]
    test "the creator facilitates by default", ctx do
      {:ok, session} = Retro.create_session(ctx.participant, ctx.team, %{title: "R"})

      assert session.facilitator_id == ctx.participant.id
      assert Retro.facilitator?(ctx.participant, session)
      refute Retro.facilitator?(ctx.facilitator, session)
    end

    @tag req: ["FR-105"]
    test "the team's defaults fill in the template and the vote budget", ctx do
      {:ok, template} =
        Teams.create_template(ctx.facilitator, ctx.team, %{
          name: "Team default",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      {:ok, team} =
        Teams.update_team_settings(ctx.facilitator, ctx.team, %{
          default_template_id: template.id,
          default_vote_budget: 9
        })

      {:ok, session} = Retro.create_session(ctx.facilitator, team, %{title: "R"})

      assert session.vote_budget == 9
      assert Enum.map(session.columns, & &1.name) == ["A", "B"]
    end

    @tag req: ["FR-917"]
    test "a session with no template still gets a usable board", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})

      assert length(session.columns) == 3
    end

    @tag req: ["FR-203"]
    test "a session may be scheduled for later", ctx do
      at = DateTime.utc_now(:second) |> DateTime.add(1, :day)

      {:ok, session} =
        Retro.create_session(ctx.facilitator, ctx.team, %{title: "R", scheduled_at: at})

      assert DateTime.compare(session.scheduled_at, at) == :eq
      assert Session.state(session) == :created
    end

    @tag req: ["FR-201"]
    test "gets a default title rather than refusing", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{})

      assert session.title =~ "Retrospective"
    end

    @tag req: ["FR-210"]
    test "the anonymous and blind modes are chosen at creation", ctx do
      {:ok, session} =
        Retro.create_session(ctx.facilitator, ctx.team, %{
          title: "R",
          is_anonymous: true,
          is_blind: true
        })

      assert session.is_anonymous
      assert session.is_blind
    end

    @tag req: ["NFR-201"]
    test "someone outside the team cannot create one", ctx do
      assert Retro.create_session(insert(:user), ctx.team, %{title: "R"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-106"]
    test "an archived team accepts no new sessions", ctx do
      archived = team_with_lead(ctx.facilitator, %{is_archived: true})

      assert Retro.create_session(ctx.facilitator, archived, %{title: "R"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-103"]
    test "another team's template cannot be borrowed", ctx do
      other_lead = insert(:user)
      other_team = team_with_lead(other_lead)

      {:ok, theirs} =
        Teams.create_template(other_lead, other_team, %{
          name: "Theirs",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      assert Retro.create_session(ctx.facilitator, ctx.team, %{
               title: "R",
               template_id: theirs.id
             }) == {:error, :not_found}
    end

    @tag req: ["FR-201"]
    test "reports validation errors rather than raising", ctx do
      assert {:error, changeset} =
               Retro.create_session(ctx.facilitator, ctx.team, %{title: "R", vote_budget: 0})

      assert %{vote_budget: [_message]} = errors_on(changeset)
    end
  end

  describe "change_session/2" do
    @tag req: ["FR-201"]
    test "builds a changeset for the create form" do
      assert %Ecto.Changeset{} = Retro.change_session()
    end
  end

  describe "form values that arrive as empty strings" do
    @tag req: ["FR-105"]
    test "an unchosen template falls back to the team default", ctx do
      {:ok, template} =
        Teams.create_template(ctx.facilitator, ctx.team, %{
          name: "Default",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      {:ok, team} =
        Teams.update_team_settings(ctx.facilitator, ctx.team, %{default_template_id: template.id})

      # An HTML select with nothing chosen submits "", not nil.
      {:ok, session} =
        Retro.create_session(ctx.facilitator, team, %{"title" => "R", "template_id" => ""})

      assert Enum.map(session.columns, & &1.name) == ["A", "B"]
    end
  end

  describe "facilitator?/2 and session_role/2" do
    @tag req: ["NFR-201"]
    test "a signed-out caller is never the facilitator", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})

      refute Retro.facilitator?(nil, session)
      assert Retro.session_role(nil, session) == :participant
    end

    @tag req: ["NFR-201"]
    test "accepts a scope, which is what the web layer carries", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})

      assert Retro.facilitator?(Scope.for_user(ctx.facilitator), session)
      refute Retro.facilitator?(Scope.for_user(ctx.participant), session)
    end
  end

  describe "fetch_session/2 and list_sessions/1" do
    setup ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-203"]
    test "a member sees their team's sessions", ctx do
      assert Enum.map(Retro.list_sessions(ctx.team), & &1.id) == [ctx.session.id]
      assert {:ok, _session} = Retro.fetch_session(ctx.participant, ctx.session.id)
    end

    @tag req: ["FR-103"]
    test "an outsider sees nothing, not even that it exists", ctx do
      assert Retro.fetch_session(insert(:user), ctx.session.id) == {:error, :not_found}
    end

    @tag req: ["FR-605"]
    test "an Org Admin does not get another team's board", ctx do
      assert Retro.fetch_session(insert(:org_admin), ctx.session.id) == {:error, :not_found}
    end

    @tag req: ["FR-203"]
    test "a session that does not exist is not found", ctx do
      assert Retro.fetch_session(ctx.facilitator, 999_999) == {:error, :not_found}
    end

    @tag req: ["FR-203"]
    test "open sessions are listed separately from closed ones", ctx do
      {:ok, active} = Retro.start_session(ctx.facilitator, ctx.session)
      {:ok, _closed} = Retro.close_session(ctx.facilitator, active)
      {:ok, upcoming} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "Next"})

      assert Enum.map(Retro.list_open_sessions(ctx.team), & &1.id) == [upcoming.id]
      assert length(Retro.list_sessions(ctx.team)) == 2
    end

    @tag req: ["NFR-503"]
    test "active sessions can be counted", ctx do
      assert Retro.count_active_sessions(ctx.team) == 0
      {:ok, _active} = Retro.start_session(ctx.facilitator, ctx.session)
      assert Retro.count_active_sessions(ctx.team) == 1
    end
  end

  describe "fetch_session_by_code/2" do
    setup ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)
      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-204"]
    test "a member joins with the code", ctx do
      assert {:ok, found} = Retro.fetch_session_by_code(ctx.participant, ctx.session.join_code)
      assert found.id == ctx.session.id
    end

    @tag req: ["FR-204"]
    test "accepts the code as a person would type it", ctx do
      messy = ctx.session.join_code |> String.downcase() |> String.replace(~r/(.{3})/, "\\1-")

      assert {:ok, _session} = Retro.fetch_session_by_code(ctx.participant, messy)
    end

    @tag req: ["FR-204"]
    test "someone outside the team cannot join, and is not told the code exists", ctx do
      assert Retro.fetch_session_by_code(insert(:user), ctx.session.join_code) ==
               {:error, :not_found}
    end

    @tag req: ["FR-204"]
    test "an unknown or empty code is not found", ctx do
      assert Retro.fetch_session_by_code(ctx.participant, "ZZZZZZ") == {:error, :not_found}
      assert Retro.fetch_session_by_code(ctx.participant, "") == {:error, :not_found}
      assert Retro.fetch_session_by_code(ctx.participant, nil) == {:error, :not_found}
    end

    @tag req: ["FR-205"]
    test "a closed session says so rather than pretending not to exist", ctx do
      {:ok, closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert Retro.fetch_session_by_code(ctx.participant, closed.join_code) ==
               {:error, :session_closed}
    end
  end

  describe "the lifecycle (FR-205)" do
    setup ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      Events.subscribe(session.id)
      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-205"]
    test "starting moves created to active and announces it", ctx do
      assert {:ok, active} = Retro.start_session(ctx.facilitator, ctx.session)
      assert Session.state(active) == :active

      assert_receive {:retro_event, "phase.changed", %{state: :active, phase: :checkin}}
    end

    @tag req: ["FR-205", "FR-215"]
    test "closing stamps the time and announces that the recap is ready", ctx do
      {:ok, active} = Retro.start_session(ctx.facilitator, ctx.session)

      assert {:ok, closed} = Retro.close_session(ctx.facilitator, active)
      assert Session.state(closed) == :closed
      assert closed.closed_at

      assert_receive {:retro_event, "session.closed", %{session_id: _id}}
    end

    @tag req: ["FR-205"]
    test "a session cannot be started twice or closed before it starts", ctx do
      {:ok, active} = Retro.start_session(ctx.facilitator, ctx.session)

      assert Retro.start_session(ctx.facilitator, active) == {:error, :wrong_state}
      assert Retro.close_session(ctx.facilitator, ctx.session) == {:error, :wrong_state}
    end

    @tag req: ["NFR-201"]
    test "only the facilitator may start or close", ctx do
      assert Retro.start_session(ctx.participant, ctx.session) == {:error, :unauthorized}

      {:ok, active} = Retro.start_session(ctx.facilitator, ctx.session)
      assert Retro.close_session(ctx.participant, active) == {:error, :unauthorized}
    end

    @tag req: ["NFR-201"]
    test "an outsider may do neither", ctx do
      assert Retro.start_session(insert(:user), ctx.session) == {:error, :unauthorized}
    end
  end

  describe "phases (FR-206)" do
    setup ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)
      Events.subscribe(session.id)
      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-206"]
    test "the facilitator advances through the six phases", ctx do
      session =
        Enum.reduce(1..5, ctx.session, fn _step, session ->
          {:ok, next} = Retro.advance_phase(ctx.facilitator, session)
          next
        end)

      assert Session.phase(session) == :wrapup
    end

    @tag req: ["FR-206"]
    test "advancing past the last phase is refused", ctx do
      {:ok, wrapup} = Retro.set_phase(ctx.facilitator, ctx.session, :wrapup)

      assert Retro.advance_phase(ctx.facilitator, wrapup) == {:error, :wrong_phase}
    end

    @tag req: ["FR-206"]
    test "the facilitator reverts to the previous phase", ctx do
      {:ok, group} = Retro.set_phase(ctx.facilitator, ctx.session, :group)

      assert {:ok, back} = Retro.revert_phase(ctx.facilitator, group)
      assert Session.phase(back) == :brainstorm
    end

    @tag req: ["FR-206"]
    test "reverting before the first phase is refused", ctx do
      assert Retro.revert_phase(ctx.facilitator, ctx.session) == {:error, :wrong_phase}
    end

    @tag req: ["FR-206"]
    test "skipping a phase is moving to one further ahead", ctx do
      assert {:ok, skipped} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      assert Session.phase(skipped) == :vote
    end

    @tag req: ["FR-206", "NFR-102"]
    test "every participant's view is told about the change", ctx do
      {:ok, _next} = Retro.advance_phase(ctx.facilitator, ctx.session)

      assert_receive {:retro_event, "phase.changed", payload}
      assert payload.phase == :brainstorm
      assert payload.state == :active
    end

    @tag req: ["NFR-201"]
    test "a participant cannot change the phase", ctx do
      assert Retro.advance_phase(ctx.participant, ctx.session) == {:error, :unauthorized}
      assert Retro.set_phase(ctx.participant, ctx.session, :vote) == {:error, :unauthorized}
    end

    @tag req: ["FR-206"]
    test "a phase that does not exist is refused", ctx do
      assert Retro.set_phase(ctx.facilitator, ctx.session, :nonsense) == {:error, :wrong_phase}
      assert Retro.set_phase(ctx.facilitator, ctx.session, nil) == {:error, :wrong_phase}
    end

    @tag req: ["FR-205"]
    test "phases cannot be changed once the session is closed", ctx do
      {:ok, closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert Retro.advance_phase(ctx.facilitator, closed) == {:error, :wrong_phase}
    end
  end

  describe "the timer (FR-208)" do
    setup ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)
      Events.subscribe(session.id)
      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-208"]
    test "starting a countdown announces it to everyone", ctx do
      assert {:ok, running} = Retro.start_timer(ctx.facilitator, ctx.session, 300)

      assert Session.timer_running?(running)
      assert Session.timer_remaining(running) <= 300

      assert_receive {:retro_event, "timer.updated", %{running: true, duration_s: 300}}
    end

    @tag req: ["FR-208"]
    test "pausing keeps what is left and stops the clock", ctx do
      {:ok, running} = Retro.start_timer(ctx.facilitator, ctx.session, 300)

      assert {:ok, paused} = Retro.pause_timer(ctx.facilitator, running)
      refute Session.timer_running?(paused)
      assert paused.timer_remaining_s <= 300

      assert_receive {:retro_event, "timer.updated", %{running: false}}
    end

    @tag req: ["FR-208"]
    test "starting again resumes from what was left", ctx do
      {:ok, running} = Retro.start_timer(ctx.facilitator, ctx.session, 300)
      {:ok, paused} = Retro.pause_timer(ctx.facilitator, running)

      assert {:ok, resumed} = Retro.start_timer(ctx.facilitator, paused)
      assert resumed.timer_duration_s == paused.timer_remaining_s
      assert Session.timer_running?(resumed)
    end

    @tag req: ["FR-208"]
    test "resetting clears the timer", ctx do
      {:ok, running} = Retro.start_timer(ctx.facilitator, ctx.session, 300)

      assert {:ok, reset} = Retro.reset_timer(ctx.facilitator, running)
      assert Session.timer_remaining(reset) == nil
      refute Session.timer_running?(reset)
    end

    @tag req: ["FR-208"]
    test "an absurd duration is refused", ctx do
      assert {:error, changeset} = Retro.start_timer(ctx.facilitator, ctx.session, 1)
      assert %{timer_duration_s: [_message]} = errors_on(changeset)
    end

    @tag req: ["NFR-201"]
    test "a participant cannot touch the timer", ctx do
      assert Retro.start_timer(ctx.participant, ctx.session, 60) == {:error, :unauthorized}
      assert Retro.pause_timer(ctx.participant, ctx.session) == {:error, :unauthorized}
      assert Retro.reset_timer(ctx.participant, ctx.session) == {:error, :unauthorized}
    end
  end

  describe "transfer_facilitator/3 (FR-207)" do
    setup ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)
      Events.subscribe(session.id)
      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-207"]
    test "the facilitator hands the role to another participant", ctx do
      assert {:ok, updated} =
               Retro.transfer_facilitator(ctx.facilitator, ctx.session, ctx.participant.id)

      assert updated.facilitator_id == ctx.participant.id
      assert Retro.facilitator?(ctx.participant, updated)
      assert Retro.session_role(ctx.facilitator, updated) == :participant

      assert_receive {:retro_event, "presence.updated", %{facilitator_id: _id}}
    end

    @tag req: ["FR-207"]
    test "the role cannot be handed to someone outside the team", ctx do
      assert Retro.transfer_facilitator(ctx.facilitator, ctx.session, insert(:user).id) ==
               {:error, :not_found}
    end

    @tag req: ["FR-207"]
    test "the role cannot be handed to a user that does not exist", ctx do
      assert Retro.transfer_facilitator(ctx.facilitator, ctx.session, 999_999) ==
               {:error, :not_found}
    end

    @tag req: ["NFR-201"]
    test "a participant cannot take the role for themselves", ctx do
      assert Retro.transfer_facilitator(ctx.participant, ctx.session, ctx.participant.id) ==
               {:error, :unauthorized}
    end
  end

  describe "promote_facilitator/2" do
    @tag req: ["FR-207"]
    test "hands the role over with nobody acting, which is what a timeout does", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)

      assert {:ok, updated} = Retro.promote_facilitator(session, ctx.participant.id)
      assert updated.facilitator_id == ctx.participant.id
    end

    @tag req: ["FR-207"]
    test "still refuses someone who is not in the team", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})

      assert Retro.promote_facilitator(session, insert(:user).id) == {:error, :not_found}
    end
  end

  describe "snapshot/2 (FR-309)" do
    @tag req: ["FR-309"]
    test "carries everything needed to render the board from nothing", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)
      {:ok, session} = Retro.start_timer(ctx.facilitator, session, 300)

      snapshot = Retro.snapshot(session)

      assert snapshot.state == :active
      assert snapshot.phase == :checkin
      assert snapshot.facilitator_id == ctx.facilitator.id
      assert snapshot.timer.running
      assert length(snapshot.columns) == 3
      assert [%{name: _name, position: 0} | _rest] = snapshot.columns
    end

    @tag req: ["FR-309"]
    test "reports the modes a client must respect before it renders anything", ctx do
      {:ok, session} =
        Retro.create_session(ctx.facilitator, ctx.team, %{
          title: "R",
          is_anonymous: true,
          is_blind: true
        })

      snapshot = Retro.snapshot(session)

      assert snapshot.is_anonymous
      assert snapshot.is_blind
      refute snapshot.cards_revealed
      refute snapshot.votes_revealed
    end
  end
end
