defmodule SprintLens.AdminTest do
  @moduledoc """
  Running the installation (FR-801 to FR-807, NFR-302, NFR-303).

  The two tests that matter most read the database directly rather than
  asking the application: after a purge, and after an erasure, no query can
  connect a person to what they wrote. Anything the app could still answer
  would mean the erasure was a filter rather than a deletion.
  """

  use SprintLens.DataCase

  alias SprintLens.Accounts
  alias SprintLens.Accounts.User
  alias SprintLens.Actions
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Admin
  alias SprintLens.Admin.AuditEvent
  alias SprintLens.Insights
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.MoodEntry
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Vote
  alias SprintLens.Teams
  alias SprintLens.Teams.Membership
  alias SprintLens.Workers.RetentionPurge

  setup do
    admin = insert(:org_admin, display_name: "Admin")
    lead = insert(:user, display_name: "Lek")
    team = team_with_lead(lead)
    member = insert(:user, display_name: "Ploy")
    join_team(member, team)

    %{admin: admin, lead: lead, member: member, team: team}
  end

  # A whole retrospective, closed: cards, a vote, a mood and an action.
  defp played(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.lead, attrs)
    {:ok, _mood} = Board.record_mood(ctx.member, session, :checkin_mood, 4)
    {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)

    {:ok, card} =
      Board.create_card(ctx.member, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, voting} = Retro.set_phase(ctx.lead, session, :vote)
    {:ok, _vote} = Board.cast_vote(ctx.member, voting, {:card, card.id})

    {:ok, discussing} = Retro.set_phase(ctx.lead, voting, :discuss)

    {:ok, action} =
      Actions.create_action(ctx.member, discussing, %{
        title: "Write the runbook",
        assignee_id: ctx.member.id
      })

    {:ok, closed} = Retro.close_session(ctx.lead, discussing)

    %{session: closed, card: card, action: action}
  end

  describe "the organisation's settings (FR-802)" do
    @tag req: ["FR-802", "FR-906"]
    test "exist from the first migration, with Thai as the default language", _ctx do
      settings = Admin.settings()

      assert settings.default_language == "th"
      assert settings.default_vote_budget == 5
      assert settings.retention_days == 365
      assert settings.ai_enabled
      assert settings.webhooks_enabled
    end

    @tag req: ["FR-802"]
    test "an Org Admin changes them", ctx do
      assert {:ok, settings} =
               Admin.update_settings(ctx.admin, %{
                 default_language: "en",
                 retention_days: 90
               })

      assert settings.default_language == "en"
      assert settings.retention_days == 90
      assert Admin.settings().retention_days == 90
    end

    @tag req: ["FR-802"]
    test "a language nobody speaks here is refused", ctx do
      assert {:error, changeset} = Admin.update_settings(ctx.admin, %{default_language: "fr"})
      assert %{default_language: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-802"]
    test "a retention period that would delete this sprint's retro is refused", ctx do
      assert {:error, changeset} = Admin.update_settings(ctx.admin, %{retention_days: 3})
      assert %{retention_days: [_message]} = errors_on(changeset)

      assert {:error, changeset} = Admin.update_settings(ctx.admin, %{retention_days: 100_000})
      assert %{retention_days: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-802"]
    test "nobody else changes them", ctx do
      assert Admin.update_settings(ctx.lead, %{retention_days: 30}) == {:error, :unauthorized}
      assert Admin.update_settings(nil, %{retention_days: 30}) == {:error, :unauthorized}
    end

    @tag req: ["FR-807"]
    test "and the change is audited, saying which setting moved", ctx do
      {:ok, _settings} = Admin.update_settings(ctx.admin, %{retention_days: 90})

      assert {:ok, [event]} = Admin.list_audit_events(ctx.admin)
      assert event.action == "settings.updated"
      assert event.actor_id == ctx.admin.id
      assert AuditEvent.detail(event) == %{"retention_days" => 90}
    end

    @tag req: ["FR-802"]
    test "a changeset is available for the form", _ctx do
      assert %Ecto.Changeset{} = Admin.change_settings()
    end
  end

  describe "the kill switches (FR-806)" do
    @tag req: ["FR-806"]
    test "both are on to begin with", _ctx do
      assert Admin.ai_enabled?()
      assert Admin.webhooks_enabled?()
    end

    @tag req: ["FR-806"]
    test "and either can be turned off", ctx do
      {:ok, _settings} = Admin.update_settings(ctx.admin, %{ai_enabled: false})

      refute Admin.ai_enabled?()
      assert Admin.webhooks_enabled?()

      {:ok, _settings} = Admin.update_settings(ctx.admin, %{webhooks_enabled: false})

      refute Admin.webhooks_enabled?()
    end

    @tag req: ["FR-807", "FR-806"]
    test "flipping one is audited", ctx do
      {:ok, _settings} = Admin.update_settings(ctx.admin, %{ai_enabled: false})

      assert {:ok, [event]} = Admin.list_audit_events(ctx.admin)
      assert AuditEvent.detail(event) == %{"ai_enabled" => false}
    end
  end

  describe "people (FR-801, FR-005)" do
    @tag req: ["FR-801"]
    test "an Org Admin lists everybody", ctx do
      assert {:ok, users} = Admin.list_users(ctx.admin)

      ids = Enum.map(users, & &1.id)
      assert ctx.admin.id in ids
      assert ctx.member.id in ids
    end

    @tag req: ["FR-801"]
    test "and nobody else does", ctx do
      assert Admin.list_users(ctx.lead) == {:error, :unauthorized}
    end

    @tag req: ["FR-005"]
    test "deactivating stops somebody signing in and revokes what they had", ctx do
      token = Accounts.generate_user_session_token(ctx.member)

      assert {:ok, deactivated} = Admin.deactivate_user(ctx.admin, ctx.member)

      refute deactivated.is_active
      assert Accounts.get_user_by_session_token(token) == nil
    end

    @tag req: ["FR-801"]
    test "but not while they are a team's only lead", ctx do
      assert {:error, :last_lead, details} = Admin.deactivate_user(ctx.admin, ctx.lead)
      assert details.team_ids == [ctx.team.id]

      # Which is what reassigning leadership is for (FR-801).
      {:ok, _membership} = Admin.reassign_leadership(ctx.admin, ctx.team, ctx.member)

      assert {:ok, _deactivated} = Admin.deactivate_user(ctx.admin, ctx.lead)
    end

    @tag req: ["FR-801"]
    test "somebody outside the team can be made its lead", ctx do
      outsider = insert(:user)

      assert {:ok, membership} = Admin.reassign_leadership(ctx.admin, ctx.team, outsider)

      assert membership.role == "lead"
      assert Teams.role(outsider, ctx.team) == :lead
    end

    @tag req: ["FR-801"]
    test "and a deactivated person can be let back in", ctx do
      {:ok, _deactivated} = Admin.deactivate_user(ctx.admin, ctx.member)

      assert {:ok, restored} = Admin.reactivate_user(ctx.admin, ctx.member)
      assert restored.is_active
    end

    @tag req: ["FR-801"]
    test "none of which anybody else may do", ctx do
      assert Admin.deactivate_user(ctx.lead, ctx.member) == {:error, :unauthorized}
      assert Admin.reactivate_user(ctx.lead, ctx.member) == {:error, :unauthorized}

      assert Admin.reassign_leadership(ctx.lead, ctx.team, ctx.member) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-807"]
    test "and every one of them is audited", ctx do
      {:ok, _} = Admin.reassign_leadership(ctx.admin, ctx.team, ctx.member)
      {:ok, _} = Admin.deactivate_user(ctx.admin, ctx.lead)
      {:ok, _} = Admin.reactivate_user(ctx.admin, ctx.lead)

      assert {:ok, events} = Admin.list_audit_events(ctx.admin)

      assert Enum.map(events, & &1.action) == [
               "user.reactivated",
               "user.deactivated",
               "team.lead_reassigned"
             ]
    end
  end

  describe "retention (FR-803, NFR-302)" do
    @tag req: ["FR-803"]
    test "finds the closed sessions older than the period", ctx do
      %{session: old} = played(ctx)
      %{session: recent} = played(ctx)

      backdate(old, 400)

      assert ctx |> then(fn _ -> Admin.expired_sessions() end) |> Enum.map(& &1.id) == [old.id]
      refute recent.id in Enum.map(Admin.expired_sessions(), & &1.id)
    end

    @tag req: ["FR-803"]
    test "and never one that is still running, however old", ctx do
      running = active_session(ctx.team, ctx.lead)
      backdate(running, 400)

      assert Admin.expired_sessions() == []
    end

    @tag req: ["FR-803"]
    test "the period is the organisation's to set", ctx do
      %{session: session} = played(ctx)
      backdate(session, 60)

      assert Admin.expired_sessions() == []

      {:ok, _settings} = Admin.update_settings(ctx.admin, %{retention_days: 30})

      assert Enum.map(Admin.expired_sessions(), & &1.id) == [session.id]
    end

    @tag req: ["FR-803"]
    test "the sweep purges what has aged out, and says how many", ctx do
      %{session: old} = played(ctx)
      %{session: recent} = played(ctx)
      backdate(old, 400)

      assert {:ok, 1} = perform_job(RetentionPurge, %{})

      assert Repo.get(Session, old.id) == nil
      assert Repo.get(Session, recent.id)
    end

    @tag req: ["FR-803"]
    test "and it can be told what day it is", ctx do
      %{session: session} = played(ctx)

      later = DateTime.utc_now() |> DateTime.add(400, :day) |> DateTime.to_iso8601()

      assert {:ok, 1} = perform_job(RetentionPurge, %{"now" => later})
      assert Repo.get(Session, session.id) == nil
    end

    @tag req: ["FR-807", "FR-803"]
    test "a scheduled purge is audited as the machine's doing", ctx do
      %{session: session} = played(ctx)
      backdate(session, 400)

      {:ok, 1} = perform_job(RetentionPurge, %{})

      assert {:ok, [event]} = Admin.list_audit_events(ctx.admin)
      assert event.action == "session.purged"
      assert event.actor_id == nil
      assert event.target == "session:#{session.id}"
    end
  end

  describe "purging on demand (FR-804)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-804"]
    test "takes the session and everything in it", ctx do
      assert {:ok, _purged} = Admin.purge_session(ctx.admin, ctx.session)

      assert Repo.get(Session, ctx.session.id) == nil
      assert Repo.get(Card, ctx.card.id) == nil
      assert Repo.aggregate(from(v in Vote), :count) == 0
      assert Repo.aggregate(from(m in MoodEntry), :count) == 0
    end

    @tag req: ["FR-804"]
    test "but the team's commitments survive it", ctx do
      {:ok, _purged} = Admin.purge_session(ctx.admin, ctx.session)

      # Section 6.4: "Action items survive with their session link cleared."
      assert action = Repo.get(ActionItem, ctx.action.id)
      assert action.session_id == nil
      assert action.title == "Write the runbook"
      assert Enum.map(Actions.list_actions(ctx.team), & &1.id) == [ctx.action.id]
    end

    @tag req: ["FR-804"]
    test "and it is gone from the archive", ctx do
      {:ok, _purged} = Admin.purge_session(ctx.admin, ctx.session)

      assert Insights.archive(ctx.team) == []
    end

    @tag req: ["FR-804"]
    test "a session that is still running is refused", ctx do
      running = active_session(ctx.team, ctx.lead)

      assert Admin.purge_session(ctx.admin, running) == {:error, :wrong_state}
      assert Repo.get(Session, running.id)
    end

    @tag req: ["FR-804"]
    test "a whole team can go, sessions and all", ctx do
      assert {:ok, _purged} = Admin.purge_team(ctx.admin, ctx.team)

      assert Repo.get(SprintLens.Teams.Team, ctx.team.id) == nil
      assert Repo.get(Session, ctx.session.id) == nil
      assert Repo.get(ActionItem, ctx.action.id) == nil
      assert Repo.aggregate(from(m in Membership), :count) == 0
    end

    @tag req: ["FR-804"]
    test "and nobody but an Org Admin may purge anything", ctx do
      assert Admin.purge_session(ctx.lead, ctx.session) == {:error, :unauthorized}
      assert Admin.purge_team(ctx.lead, ctx.team) == {:error, :unauthorized}
    end

    @tag req: ["FR-807", "FR-804"]
    test "each purge is audited, with who and what", ctx do
      {:ok, _purged} = Admin.purge_session(ctx.admin, ctx.session)

      assert {:ok, [event]} = Admin.list_audit_events(ctx.admin)
      assert event.action == "session.purged"
      assert event.actor_id == ctx.admin.id
      assert AuditEvent.detail(event)["team_id"] == ctx.team.id
    end
  end

  describe "PDPA erasure (FR-805, NFR-303)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-805"]
    test "no query can connect the person to what they wrote", ctx do
      assert {:ok, _erased} = Admin.erase_user(ctx.admin, ctx.member)

      # Read straight from the database, the same way the anonymity tests do.
      assert Repo.get(Card, ctx.card.id).author_id == nil
      assert Repo.all(from v in Vote, select: v.voter_id) == [nil]
      assert Repo.all(from m in MoodEntry, select: m.user_id) == [nil]
      assert Repo.get(ActionItem, ctx.action.id).assignee_id == nil
    end

    @tag req: ["FR-805"]
    test "and the account keeps nothing that says who they were", ctx do
      {:ok, erased} = Admin.erase_user(ctx.admin, ctx.member)

      refute erased.display_name == "Ploy"
      refute erased.email =~ "@example.com"
      assert erased.avatar_url == nil
      assert erased.hashed_password == nil
      refute erased.is_active
      assert User.erased?(erased)
    end

    @tag req: ["FR-805", "NFR-206"]
    test "their sessions are revoked and their memberships gone", ctx do
      token = Accounts.generate_user_session_token(ctx.member)

      {:ok, _erased} = Admin.erase_user(ctx.admin, ctx.member)

      assert Accounts.get_user_by_session_token(token) == nil
      assert Teams.role(ctx.member, ctx.team) == nil
    end

    @tag req: ["FR-805", "FR-606"]
    test "but the aggregates built from them remain", ctx do
      {:ok, _erased} = Admin.erase_user(ctx.admin, ctx.member)

      # Section 6.4: "aggregates built from them remain, de-identified."
      assert [entry] = Insights.archive(ctx.team)
      assert entry.participant_count == 1
      assert entry.card_count == 1
      assert entry.mood == 4.0
    end

    @tag req: ["FR-805"]
    test "the cards themselves are not deleted, only unsigned", ctx do
      {:ok, _erased} = Admin.erase_user(ctx.admin, ctx.member)

      assert [card] = Board.list_cards(ctx.session)
      assert card.text == "Deploys are slow"
      assert card.author_id == nil
    end

    @tag req: ["FR-805"]
    test "and the rest of the team's screens still work afterwards", ctx do
      {:ok, _erased} = Admin.erase_user(ctx.admin, ctx.member)

      assert {:ok, metrics} = Insights.team_metrics(ctx.lead, ctx.team)
      assert metrics.member_count == 1
      assert Actions.list_my_actions(ctx.lead) == []
      assert [%{assignee: nil}] = Actions.list_open_actions(ctx.team)
    end

    @tag req: ["FR-805"]
    test "nobody but an Org Admin may erase anybody", ctx do
      assert Admin.erase_user(ctx.lead, ctx.member) == {:error, :unauthorized}
    end

    @tag req: ["FR-807", "FR-805"]
    test "and the erasure is audited without naming the person erased", ctx do
      {:ok, _erased} = Admin.erase_user(ctx.admin, ctx.member)

      assert {:ok, [event]} = Admin.list_audit_events(ctx.admin)
      assert event.action == "user.erased"
      assert event.target == "user:#{ctx.member.id}"
      refute event |> AuditEvent.detail() |> inspect() |> String.contains?("Ploy")
    end
  end

  describe "rights that were revoked a moment ago (NFR-201)" do
    @tag req: ["NFR-201"]
    test "an administrator's own copy of themselves is not the authority", ctx do
      # The struct in hand still says org admin; the database does not.
      {:ok, _demoted} = Accounts.set_org_admin(ctx.admin, false)

      assert Admin.list_users(ctx.admin) == {:error, :unauthorized}
      assert Admin.update_settings(ctx.admin, %{retention_days: 90}) == {:error, :unauthorized}
      assert Admin.deactivate_user(ctx.admin, ctx.member) == {:error, :unauthorized}
      assert Admin.erase_user(ctx.admin, ctx.member) == {:error, :unauthorized}
    end
  end

  describe "the audit log (FR-807)" do
    @tag req: ["FR-807"]
    test "records who, what, when and which thing", ctx do
      {:ok, event} =
        Admin.record_event(ctx.admin, "session.purged", "session:7", %{team_id: 3})

      assert event.actor_id == ctx.admin.id
      assert event.action == "session.purged"
      assert event.target == "session:7"
      assert event.inserted_at
      assert AuditEvent.detail(event) == %{"team_id" => 3}
    end

    @tag req: ["FR-807", "NFR-502"]
    test "and never anything personal, even when a caller passes some", ctx do
      {:ok, event} =
        Admin.record_event(ctx.admin, "user.erased", "user:7", %{
          email: "ploy@example.com",
          secret: "hunter2",
          team_id: 3
        })

      detail = AuditEvent.detail(event)

      refute detail["email"] == "ploy@example.com"
      refute detail["secret"] == "hunter2"
      assert detail["team_id"] == 3
    end

    @tag req: ["FR-807"]
    test "an event with no detail is fine", ctx do
      {:ok, event} = Admin.record_event(ctx.admin, "user.deactivated", "user:7")

      assert AuditEvent.detail(event) == %{}
    end

    @tag req: ["FR-807"]
    test "the machine's own actions have no actor", _ctx do
      {:ok, event} = Admin.record_event(:system, "session.purged", "session:7")

      assert event.actor_id == nil
    end

    @tag req: ["FR-807"]
    test "newest first, and bounded", ctx do
      for n <- 1..5, do: Admin.record_event(ctx.admin, "user.deactivated", "user:#{n}")

      assert {:ok, events} = Admin.list_audit_events(ctx.admin, 2)
      assert length(events) == 2
      assert hd(events).target == "user:5"
    end

    @tag req: ["FR-807"]
    test "and only an Org Admin reads it", ctx do
      assert Admin.list_audit_events(ctx.lead) == {:error, :unauthorized}
    end
  end

  defp backdate(session, days) do
    at = DateTime.add(DateTime.utc_now(:second), -days, :day)

    Repo.update_all(
      from(s in Session, where: s.id == ^session.id),
      set: [closed_at: at, inserted_at: at]
    )
  end
end
