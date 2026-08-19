defmodule SprintLens.InsightsTest do
  @moduledoc """
  The archive, the recap, search and the dashboard numbers (FR-601 to FR-606).

  Two things here are promises rather than features, and get the most
  attention: search must not become a way around blind mode, and the org-wide
  view must contain no card text and no name at all.
  """

  use SprintLens.DataCase

  alias SprintLens.Actions
  alias SprintLens.Insights
  alias SprintLens.Retro
  alias SprintLens.Retro.Board

  setup do
    facilitator = insert(:user, display_name: "Lek")
    team = team_with_lead(facilitator)
    participant = insert(:user, display_name: "Ploy")
    join_team(participant, team)

    %{team: team, facilitator: facilitator, participant: participant}
  end

  # A whole retrospective, played out and closed: cards, a cluster, votes, a
  # note, a mood, a ROTI score and an action.
  defp played(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.facilitator, attrs)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :checkin)
    {:ok, _mood} = Board.record_mood(ctx.participant, session, :checkin_mood, 4, "steady")
    {:ok, _mood} = Board.record_mood(ctx.facilitator, session, :checkin_mood, 2)

    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)
    column = hd(session.columns)

    cards =
      for text <- ["Deploys are slow", "การรีวิวช้ามาก", "Good pairing"] do
        {:ok, card} =
          Board.create_card(ctx.participant, session, %{column_id: column.id, text: text})

        card
      end

    {:ok, grouping} = Retro.set_phase(ctx.facilitator, session, :group)

    {:ok, group} =
      Board.create_group(ctx.participant, grouping, "Tooling", [hd(cards).id])

    {:ok, voting} = Retro.set_phase(ctx.facilitator, grouping, :vote)
    {:ok, _vote} = Board.cast_vote(ctx.participant, voting, {:group, group.id})

    {:ok, discussing} = Retro.set_phase(ctx.facilitator, voting, :discuss)

    {:ok, _note} =
      Board.write_note(ctx.facilitator, discussing, {:group, group.id}, "Fix the build first")

    {:ok, action} =
      Actions.create_action(ctx.participant, discussing, %{title: "Write the runbook"})

    {:ok, wrapping} = Retro.set_phase(ctx.facilitator, discussing, :wrapup)
    {:ok, _roti} = Board.record_mood(ctx.participant, wrapping, :roti, 5)

    {:ok, closed} = Retro.close_session(ctx.facilitator, wrapping)

    %{session: closed, cards: cards, group: group, action: action}
  end

  describe "the archive (FR-601)" do
    @tag req: ["FR-601"]
    test "lists closed sessions with what happened in them", ctx do
      %{session: closed} = played(ctx)

      assert [entry] = Insights.archive(ctx.team)

      assert entry.session.id == closed.id
      assert entry.closed_at
      assert entry.participant_count == 2
      assert entry.card_count == 3
      assert entry.mood == 3.0
      assert entry.roti == 5.0
    end

    @tag req: ["FR-601"]
    test "names the template a session used", ctx do
      template = insert(:template, team: ctx.team, name: "Sailboat")
      played(ctx, %{template_id: template.id})

      assert [%{template: "Sailboat"}] = Insights.archive(ctx.team)
    end

    @tag req: ["FR-601"]
    test "a session still running is not in the archive", ctx do
      active_session(ctx.team, ctx.facilitator)

      assert Insights.archive(ctx.team) == []
    end

    @tag req: ["FR-601"]
    test "most recently closed first", ctx do
      %{session: first} = played(ctx)
      %{session: second} = played(ctx)

      assert Insights.archive(ctx.team) |> Enum.map(& &1.session.id) == [second.id, first.id]
    end

    @tag req: ["FR-601", "NFR-304"]
    test "an anonymous session still says how many people were there", ctx do
      %{session: closed} = played(ctx, %{is_anonymous: true})

      # The references were destroyed at close; the number was taken first
      # (section 6.4, "aggregates built from them remain, de-identified").
      assert [%{participant_count: 2}] = Insights.archive(ctx.team)
      assert Enum.all?(Board.list_cards(closed), &is_nil(&1.author_id))
    end
  end

  describe "the recap (FR-602, FR-215)" do
    @tag req: ["FR-602"]
    test "carries everything the session produced", ctx do
      %{session: closed, action: action} = played(ctx)

      recap = Insights.recap(closed, ctx.participant)

      assert length(recap.columns) == 3
      assert length(recap.cards) == 3
      assert Enum.any?(recap.topics, &(&1.kind == :group))
      assert [note] = recap.notes
      assert note.body == "Fix the build first"
      assert [%{id: id}] = recap.actions
      assert id == action.id
      assert recap.mood.average == 3.0
      assert recap.roti.average == 5.0
      assert recap.participant_count == 2
    end

    @tag req: ["FR-404", "FR-602"]
    test "the vote totals are out, because closing revealed them", ctx do
      %{session: closed, group: group} = played(ctx)

      recap = Insights.recap(closed, ctx.participant)
      topic = Enum.find(recap.topics, &(&1.id == group.id and &1.kind == :group))

      assert topic.votes == 1
    end

    @tag req: ["FR-210", "FR-602"]
    test "an anonymous session's recap has nobody's name in it", ctx do
      %{session: closed} = played(ctx, %{is_anonymous: true})

      recap = Insights.recap(closed, ctx.facilitator)

      assert Enum.all?(recap.cards, &is_nil(&1.author_id))
      refute recap |> inspect(limit: :infinity) |> String.contains?("Ploy")
    end

    @tag req: ["FR-602"]
    test "a recap is only for a session that has finished", ctx do
      running = active_session(ctx.team, ctx.facilitator)
      %{session: closed} = played(ctx)

      assert {:ok, _session} = Insights.fetch_closed_session(ctx.participant, closed.id)
      assert Insights.fetch_closed_session(ctx.participant, running.id) == {:error, :not_found}
    end

    @tag req: ["FR-103"]
    test "and only for someone in the team", ctx do
      %{session: closed} = played(ctx)

      assert Insights.fetch_closed_session(insert(:user), closed.id) == {:error, :not_found}
      assert Insights.fetch_closed_session(ctx.participant, 0) == {:error, :not_found}
    end
  end

  describe "search (FR-603)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-603"]
    test "finds a card by a word in it", ctx do
      assert {:ok, results} = Insights.search(ctx.participant, ctx.team, "deploys")

      assert Enum.map(results.cards, & &1.text) == ["Deploys are slow"]
      assert results.notes == []
    end

    @tag req: ["FR-603", "FR-906"]
    test "and finds Thai text inside a sentence with no spaces in it", ctx do
      # The reason this app searches with a substring match rather than FTS5:
      # every FTS5 tokenizer splits on whitespace, and Thai does not have any.
      assert {:ok, results} = Insights.search(ctx.participant, ctx.team, "รีวิว")

      assert Enum.map(results.cards, & &1.text) == ["การรีวิวช้ามาก"]
    end

    @tag req: ["FR-603"]
    test "finds a discussion note", ctx do
      assert {:ok, results} = Insights.search(ctx.participant, ctx.team, "build first")

      assert [note] = results.notes
      assert note.body == "Fix the build first"
    end

    @tag req: ["FR-603"]
    test "finds an action item by title or description", ctx do
      assert {:ok, results} = Insights.search(ctx.participant, ctx.team, "runbook")
      assert [item] = results.actions
      assert item.title == "Write the runbook"

      {:ok, _updated} =
        Actions.update_action(ctx.participant, ctx.action, %{description: "ask the SRE team"})

      assert {:ok, described} = Insights.search(ctx.participant, ctx.team, "SRE")
      assert length(described.actions) == 1
    end

    @tag req: ["FR-603"]
    test "matches without caring about case", ctx do
      assert {:ok, results} = Insights.search(ctx.participant, ctx.team, "DEPLOYS")

      assert length(results.cards) == 1
    end

    @tag req: ["FR-209", "FR-603"]
    test "a session that is still running is not searchable", ctx do
      running = active_session(ctx.team, ctx.facilitator, %{is_blind: true})
      {:ok, running} = Retro.set_phase(ctx.facilitator, running, :brainstorm)

      {:ok, _secret} =
        Board.create_card(ctx.facilitator, running, %{
          column_id: hd(running.columns).id,
          text: "Deploys are still slow"
        })

      # Blind mode is a promise about a live board. A search box that answered
      # from it would be the way around FR-209.
      assert {:ok, results} = Insights.search(ctx.participant, ctx.team, "deploys")
      assert Enum.map(results.cards, & &1.text) == ["Deploys are slow"]
    end

    @tag req: ["FR-603"]
    test "a wildcard character is a character, not a wildcard", ctx do
      {:ok, _card} = literal_card(ctx, "100% done")

      assert {:ok, everything} = Insights.search(ctx.participant, ctx.team, "%")
      assert Enum.map(everything.cards, & &1.text) == ["100% done"]

      assert {:ok, underscore} = Insights.search(ctx.participant, ctx.team, "_")
      assert underscore.cards == []
    end

    @tag req: ["FR-603"]
    test "an empty search is not a search for everything", ctx do
      assert Insights.search(ctx.participant, ctx.team, "   ") == {:error, :empty_query}
      assert Insights.search(ctx.participant, ctx.team, nil) == {:error, :empty_query}
    end

    @tag req: ["FR-103"]
    test "and someone outside the team searches nothing", ctx do
      assert Insights.search(insert(:user), ctx.team, "deploys") == {:error, :unauthorized}
      assert Insights.search(nil, ctx.team, "deploys") == {:error, :unauthorized}
    end
  end

  describe "the team dashboard (FR-604)" do
    @tag req: ["FR-604"]
    test "a team with no history has an empty dashboard rather than an error", ctx do
      assert {:ok, metrics} = Insights.team_metrics(ctx.participant, ctx.team)

      assert metrics.session_count == 0
      assert metrics.mood_trend == []
      assert metrics.actions.total == 0
    end

    @tag req: ["FR-604"]
    test "trends are a point per session, oldest first", ctx do
      %{session: first} = played(ctx)
      %{session: second} = played(ctx)

      assert {:ok, metrics} = Insights.team_metrics(ctx.participant, ctx.team)

      assert Enum.map(metrics.mood_trend, & &1.session_id) == [first.id, second.id]
      assert Enum.map(metrics.mood_trend, & &1.value) == [3.0, 3.0]
      assert Enum.map(metrics.roti_trend, & &1.value) == [5.0, 5.0]
      assert Enum.map(metrics.cards_per_session, & &1.value) == [3, 3]
    end

    @tag req: ["FR-604"]
    test "participation is what fraction of the team took part", ctx do
      played(ctx)

      assert {:ok, metrics} = Insights.team_metrics(ctx.participant, ctx.team)

      assert metrics.member_count == 2
      assert Enum.map(metrics.participation, & &1.value) == [100.0]
    end

    @tag req: ["FR-604"]
    test "a session nobody answered leaves a gap, not a zero", ctx do
      quiet = active_session(ctx.team, ctx.facilitator)
      {:ok, _closed} = Retro.close_session(ctx.facilitator, quiet)

      assert {:ok, metrics} = Insights.team_metrics(ctx.participant, ctx.team)

      assert [%{value: nil}] = metrics.mood_trend
      assert [%{value: 0.0}] = metrics.participation
    end

    @tag req: ["FR-506", "FR-604"]
    test "action completion and ageing come from the action list itself", ctx do
      %{action: action} = played(ctx)
      {:ok, _done} = Actions.update_action(ctx.participant, action, %{status: "done"})

      assert {:ok, metrics} = Insights.team_metrics(ctx.participant, ctx.team)

      assert metrics.actions == Actions.stats(ctx.team)
      assert metrics.actions.completion_rate == 100.0
    end

    @tag req: ["FR-103"]
    test "and a team you are not in has no dashboard for you", ctx do
      assert Insights.team_metrics(insert(:user), ctx.team) == {:error, :unauthorized}
    end
  end

  describe "the org-wide view (FR-605)" do
    @tag req: ["FR-605"]
    test "an Org Admin sees aggregates for every team", ctx do
      played(ctx)
      admin = insert(:org_admin)

      assert {:ok, metrics} = Insights.org_metrics(admin)

      assert metrics.team_count >= 1
      row = Enum.find(metrics.teams, &(&1.team_id == ctx.team.id))
      assert row.session_count == 1
      assert row.mood_average == 3.0
      assert row.open_actions == 1
    end

    @tag req: ["FR-605", "FR-606"]
    test "and nothing that says who wrote what", ctx do
      played(ctx, %{is_anonymous: false})
      admin = insert(:org_admin)

      {:ok, metrics} = Insights.org_metrics(admin)
      rendered = inspect(metrics, limit: :infinity)

      # No card text and no person, for a session that was not even anonymous
      # — FR-605 is about the org view, not about the session's mode.
      refute rendered =~ "Deploys are slow"
      refute rendered =~ "Fix the build first"
      refute rendered =~ "Ploy"
      refute rendered =~ "Lek"
    end

    @tag req: ["FR-605"]
    test "totals across the organisation", ctx do
      played(ctx)
      admin = insert(:org_admin)

      {:ok, metrics} = Insights.org_metrics(admin)

      assert metrics.totals.session_count >= 1
      assert metrics.totals.open_actions >= 1
      assert metrics.totals.mood_average == 3.0
    end

    @tag req: ["FR-605"]
    test "and nobody else sees it at all", ctx do
      assert Insights.org_metrics(ctx.facilitator) == {:error, :unauthorized}
      assert Insights.org_metrics(nil) == {:error, :unauthorized}
    end
  end

  defp literal_card(ctx, text) do
    session = active_session(ctx.team, ctx.facilitator)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    {:ok, card} =
      Board.create_card(ctx.participant, session, %{column_id: hd(session.columns).id, text: text})

    {:ok, _closed} = Retro.close_session(ctx.facilitator, session)

    {:ok, card}
  end
end
