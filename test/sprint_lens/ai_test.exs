defmodule SprintLens.AITest do
  @moduledoc """
  The AI module (AI-001 to AI-018).

  The test this whole module is built around is that nothing here writes to
  the board. AI-002 says a human must accept, edit or reject; the way that is
  guaranteed is architectural — accepting a cluster calls `Board`, accepting
  an action fills in a form, and `SprintLens.AI` has no board write of its
  own. So these tests check what accepting *did*, not only that a status
  changed.
  """

  use SprintLens.DataCase

  import ExUnit.CaptureLog

  alias SprintLens.Actions
  alias SprintLens.Admin
  alias SprintLens.AI
  alias SprintLens.AI.FakeAdapter
  alias SprintLens.AI.Scope
  alias SprintLens.AI.Suggestion
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLens.Workers.AiSuggestion, as: Worker

  setup do
    lead = insert(:user, display_name: "Lek")
    team = team_with_lead(lead)
    member = insert(:user, display_name: "Ploy")
    join_team(member, team)

    {:ok, team} = Teams.update_team_settings(lead, team, %{ai_opt_in: true})

    %{team: team, lead: lead, member: member}
  end

  # A closed retrospective with cards, a cluster, a vote and a note.
  defp played(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.lead, attrs)
    {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)

    cards =
      for text <- ["Deploys are slow", "Flaky CI", "Good pairing"] do
        {:ok, card} =
          Board.create_card(ctx.member, session, %{column_id: hd(session.columns).id, text: text})

        card
      end

    {:ok, grouping} = Retro.set_phase(ctx.lead, session, :group)
    {:ok, group} = Board.create_group(ctx.member, grouping, "Tooling", [hd(cards).id])

    {:ok, voting} = Retro.set_phase(ctx.lead, grouping, :vote)
    {:ok, _vote} = Board.cast_vote(ctx.member, voting, {:group, group.id})

    {:ok, discussing} = Retro.set_phase(ctx.lead, voting, :discuss)

    {:ok, _note} =
      Board.write_note(ctx.lead, discussing, {:group, group.id}, "Fix the build first")

    {:ok, closed} = Retro.close_session(ctx.lead, discussing)

    %{session: closed, cards: cards, group: group}
  end

  # Runs the job the request actually queued, with the arguments it actually
  # queued — a hand-written args map would quietly drop the extras a feature
  # like the action draft depends on.
  defp run(suggestion) do
    args = queued_args(suggestion)

    case perform_job(Worker, args) do
      {:ok, _id} -> :ok
      :ok -> :ok
      other -> raise "job did not finish: #{inspect(other)}"
    end

    Repo.get(Suggestion, suggestion.id)
  end

  defp attach_telemetry do
    parent = self()
    handler = "ai-job-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:sprint_lens, :ai, :job],
      fn _event, measurements, metadata, _config ->
        send(parent, {:ai_job, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  # Filtered in Elixir rather than in SQL. `json_extract` is SQLite's; asking
  # PostgreSQL for it is an undefined function, and a test suite that only
  # runs against one of the two databases is not testing the other.
  defp queued_args(suggestion) do
    args =
      Repo.all(from j in Oban.Job, order_by: [desc: j.id], select: j.args)

    Enum.find(args, &(&1["suggestion_id"] == suggestion.id)) ||
      flunk("no job was queued for suggestion #{suggestion.id}")
  end

  describe "whether AI is available at all (AI-001, AI-003)" do
    @tag req: ["AI-003"]
    test "needs the team to have opted in", ctx do
      assert AI.available?(ctx.team)

      {:ok, opted_out} = Teams.update_team_settings(ctx.lead, ctx.team, %{ai_opt_in: false})

      refute AI.available?(opted_out)
      refute AI.available?(nil)
    end

    @tag req: ["AI-003", "FR-806"]
    test "and the organisation's kill switch to be off", ctx do
      admin = insert(:org_admin)
      {:ok, _settings} = Admin.update_settings(admin, %{ai_enabled: false})

      refute AI.available?(ctx.team)
    end

    @tag req: ["AI-003"]
    test "asking anyway is refused, and says why", ctx do
      %{session: session} = played(ctx)
      {:ok, opted_out} = Teams.update_team_settings(ctx.lead, ctx.team, %{ai_opt_in: false})

      assert AI.request(ctx.lead, opted_out, :session_summary, %{session: session}) ==
               {:error, :ai_disabled}
    end

    @tag req: ["FR-103"]
    test "and somebody outside the team cannot ask at all", ctx do
      %{session: session} = played(ctx)

      assert AI.request(insert(:user), ctx.team, :session_summary, %{session: session}) ==
               {:error, :unauthorized}

      refute AI.can_request?(insert(:user), ctx.team)
      assert AI.can_request?(ctx.member, ctx.team)
    end
  end

  describe "asking for a suggestion (AI-005)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-005"]
    test "returns at once, queued, with a job behind it", ctx do
      assert {:ok, suggestion} =
               AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      assert Suggestion.status(suggestion) == :queued
      assert Suggestion.type(suggestion) == :session_summary
      assert suggestion.session_id == ctx.session.id
      assert suggestion.requested_by_id == ctx.lead.id
      assert Suggestion.input_scope(suggestion) == ~w(cards groups votes notes)
      assert suggestion.input_bytes > 0

      assert [job] = Repo.all(Oban.Job)
      assert job.args["suggestion_id"] == suggestion.id
    end

    @tag req: ["AI-005"]
    test "and the job fills it in", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      ready = run(suggestion)

      assert Suggestion.status(ready) == :ready
      assert ready.output =~ "## Summary"
      assert ready.output =~ "Deploys are slow"
      assert ready.duration_ms >= 0
    end

    @tag req: ["AI-005"]
    test "a type nobody offers is not a suggestion", ctx do
      assert AI.request(ctx.lead, ctx.team, :horoscope, %{session: ctx.session}) ==
               {:error, :not_found}
    end

    @tag req: ["AI-005"]
    test "and a job whose suggestion has gone is cancelled rather than retried", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      Repo.delete!(suggestion)

      assert {:cancel, :suggestion_gone} =
               perform_job(Worker, %{"suggestion_id" => suggestion.id})
    end

    @tag req: ["AI-009", "AI-010", "AI-011", "AI-012", "AI-013", "AI-014"]
    test "every feature of section 5.4 can be asked for", ctx do
      requests = [
        {:session_summary, %{session: ctx.session}},
        {:clustering, %{session: ctx.session}},
        {:action_draft, %{session: ctx.session, topic: "Tooling", note: "Fix the build"}},
        {:recurring_themes, %{}},
        {:icebreakers, %{language: "th"}},
        {:translation, %{text: "การรีวิวช้ามาก", language: "en"}}
      ]

      for {type, context} <- requests do
        assert {:ok, suggestion} = AI.request(ctx.lead, ctx.team, type, context)
        ready = run(suggestion)

        assert Suggestion.status(ready) == :ready, "#{type} did not become ready"
        assert ready.output != ""
      end
    end
  end

  describe "the features that look across sessions or outside them" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-012"]
    test "recurring themes look at the team's past retrospectives", ctx do
      played(ctx)

      {:ok, input, scope} = Scope.build(:recurring_themes, %{team: ctx.team})

      assert scope == ~w(recaps)
      assert length(input.sessions) == 2
      assert Enum.all?(input.sessions, &Map.has_key?(&1, :session_id))
      assert Enum.any?(input.sessions, fn s -> Enum.any?(s.cards, &(&1.text =~ "Deploys")) end)
    end

    @tag req: ["AI-013"]
    test "an icebreaker asks in the team's language and says nothing about the team", ctx do
      {:ok, input, scope} = Scope.build(:icebreakers, %{team: ctx.team, language: "th"})

      assert scope == []
      assert input == %{language: "th"}

      {:ok, suggestion} = AI.request(ctx.lead, ctx.team, :icebreakers, %{language: "th"})
      assert run(suggestion).output =~ "th"
    end

    @tag req: ["AI-014"]
    test "a translation carries the text and nothing else", ctx do
      {:ok, input, scope} = Scope.build(:translation, %{text: "การรีวิวช้ามาก", language: "en"})

      assert scope == ~w(text)
      assert input == %{text: "การรีวิวช้ามาก", to: "en"}

      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :translation, %{text: "การรีวิวช้ามาก", language: "en"})

      ready = run(suggestion)

      assert ready.output =~ "การรีวิวช้ามาก"
      assert ready.output =~ "[en]"
    end
  end

  describe "when the model does not answer (AI-006)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-006"]
    test "the failure is recorded and the slot offers a retry", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      FakeAdapter.fail(:provider_unavailable)
      failed = run(suggestion)

      assert Suggestion.status(failed) == :failed
      assert failed.error =~ "provider_unavailable"

      # AI-006's "retry option": a fresh request, so the failure stays
      # countable.
      FakeAdapter.succeed()
      assert {:ok, retried} = AI.retry(ctx.lead, failed)
      assert Suggestion.status(run(retried)) == :ready
      assert retried.id != failed.id
    end

    @tag req: ["AI-006"]
    test "a timeout is a failure like any other", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      FakeAdapter.time_out()
      failed = run(suggestion)

      assert Suggestion.status(failed) == :failed
      assert failed.error =~ "timeout"
    end

    @tag req: ["AI-001", "AI-006"]
    test "and the retrospective carries on regardless", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      FakeAdapter.fail()
      run(suggestion)

      # The core flow is untouched: the recap still reads, the actions still
      # work, nothing about the session changed.
      assert %Session{summary: nil} = Repo.get(Session, ctx.session.id)
      assert length(Board.list_cards(ctx.session)) == 3
    end

    @tag req: ["AI-006"]
    test "the job has a timeout and the queue has a cap", _ctx do
      assert Worker.timeout_ms() == 60_000

      # AI-006's concurrency cap is the queue's own limit, configured beside
      # the rest of Oban rather than invented in the worker.
      assert Application.get_env(:sprint_lens, Oban)[:queues][:ai] == 2
    end
  end

  describe "the job's own edges" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-006"]
    test "an adapter that blows up is a failure, not a crash", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      FakeAdapter.raise_error("the provider exploded")
      failed = run(suggestion)

      assert Suggestion.status(failed) == :failed
      assert failed.error =~ "exploded"
    end

    @tag req: ["AI-015"]
    test "a job whose input cannot be assembled fails rather than sending nothing", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :translation, %{text: "การรีวิวช้ามาก"})

      # The job carries the extras; without them there is nothing to
      # translate, and a request for a translation of nothing is not one.
      perform_job(Worker, %{"suggestion_id" => suggestion.id, "context" => %{}})

      assert Suggestion.status(Repo.get(Suggestion, suggestion.id)) == :failed
    end

    @tag req: ["AI-005"]
    test "a job whose session has gone fails rather than raising", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      Repo.update_all(
        from(s in Suggestion, where: s.id == ^suggestion.id),
        set: [session_id: nil]
      )

      # With no session the summary scope cannot be built, which is a
      # failure the slot can offer a retry for rather than a crashed job.
      perform_job(Worker, %{"suggestion_id" => suggestion.id, "context" => %{}})

      assert Suggestion.status(Repo.get(Suggestion, suggestion.id)) == :failed
    end

    @tag req: ["AI-006"]
    test "retrying a team-wide suggestion needs no session", ctx do
      {:ok, suggestion} = AI.request(ctx.lead, ctx.team, :recurring_themes, %{})

      FakeAdapter.fail()
      failed = run(suggestion)
      FakeAdapter.succeed()

      assert {:ok, retried} = AI.retry(ctx.lead, failed)
      assert retried.session_id == nil
      assert Suggestion.status(run(retried)) == :ready
    end

    @tag req: ["AI-005"]
    test "and a scope passed as a struct is the same as one passed as a user", ctx do
      scope = %SprintLens.Accounts.Scope{user: ctx.lead}

      assert {:ok, suggestion} =
               AI.request(scope, ctx.team, :session_summary, %{session: ctx.session})

      assert suggestion.requested_by_id == ctx.lead.id
    end
  end

  describe "the human's decision (AI-002)" do
    setup ctx do
      state = played(ctx)

      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: state.session})

      Map.merge(ctx, Map.put(state, :suggestion, run(suggestion)))
    end

    @tag req: ["AI-002", "AI-009"]
    test "accepting a summary attaches it to the recap", ctx do
      assert %Session{summary: nil} = Repo.get(Session, ctx.session.id)

      assert {:ok, accepted} = AI.accept(ctx.lead, ctx.suggestion)

      assert Suggestion.status(accepted) == :accepted
      assert Repo.get(Session, ctx.session.id).summary =~ "## Summary"
    end

    @tag req: ["AI-002"]
    test "a human's edit is what gets kept, not the model's words", ctx do
      assert {:ok, accepted} =
               AI.accept(ctx.lead, ctx.suggestion, "## What we agreed\n\nShip it.")

      assert accepted.accepted_output == "## What we agreed\n\nShip it."
      assert accepted.output =~ "## Summary"
      assert Repo.get(Session, ctx.session.id).summary == "## What we agreed\n\nShip it."
    end

    @tag req: ["AI-002"]
    test "rejecting attaches nothing", ctx do
      assert {:ok, rejected} = AI.reject(ctx.lead, ctx.suggestion)

      assert Suggestion.status(rejected) == :rejected
      assert %Session{summary: nil} = Repo.get(Session, ctx.session.id)
    end

    @tag req: ["AI-002"]
    test "a decision is made once", ctx do
      {:ok, accepted} = AI.accept(ctx.lead, ctx.suggestion)

      assert AI.accept(ctx.lead, accepted) == {:error, :wrong_state}
      assert AI.reject(ctx.lead, accepted) == {:error, :wrong_state}
    end

    @tag req: ["AI-002"]
    test "and one that is not ready cannot be accepted", ctx do
      {:ok, queued} = AI.request(ctx.lead, ctx.team, :clustering, %{session: ctx.session})

      assert AI.accept(ctx.lead, queued) == {:error, :wrong_state}
    end

    @tag req: ["FR-103"]
    test "somebody outside the team decides nothing", ctx do
      assert AI.accept(insert(:user), ctx.suggestion) == {:error, :unauthorized}
      assert AI.reject(insert(:user), ctx.suggestion) == {:error, :unauthorized}
    end

    @tag req: ["AI-005"]
    test "and a suggestion is only readable by the team it belongs to", ctx do
      assert {:ok, found} = AI.fetch_suggestion(ctx.member, ctx.suggestion.id)
      assert found.id == ctx.suggestion.id

      assert AI.fetch_suggestion(insert(:user), ctx.suggestion.id) == {:error, :not_found}
      assert AI.fetch_suggestion(ctx.member, 0) == {:error, :not_found}
    end
  end

  describe "what a job may be told (AI-015, AI-016)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-016", "NFR-305"]
    test "no scope carries anybody's name, for any session", ctx do
      contexts = [
        {:session_summary, %{session: ctx.session}},
        {:clustering, %{session: ctx.session}},
        {:action_draft, %{session: ctx.session, topic: "Tooling"}},
        {:recurring_themes, %{team: ctx.team}},
        {:icebreakers, %{team: ctx.team}},
        {:translation, %{text: "hello"}}
      ]

      for {type, context} <- contexts do
        assert {:ok, input, _scope} = Scope.build(type, Map.put(context, :team, ctx.team))
        encoded = Jason.encode!(input)

        refute encoded =~ "Ploy", "#{type} carried a name"
        refute encoded =~ "Lek", "#{type} carried a name"
        refute encoded =~ "author"
        refute encoded =~ ctx.member.email
      end
    end

    @tag req: ["AI-016"]
    test "and that is true whether or not the session was anonymous", ctx do
      %{session: anonymous} = played(ctx, %{is_anonymous: true})

      for session <- [ctx.session, anonymous] do
        {:ok, input, _scope} = Scope.build(:session_summary, %{session: session})

        refute input |> Jason.encode!() |> String.contains?("Ploy")
      end
    end

    @tag req: ["AI-015"]
    test "each job is told what it needs and nothing more", ctx do
      {:ok, summary, summary_scope} = Scope.build(:session_summary, %{session: ctx.session})
      {:ok, clustering, clustering_scope} = Scope.build(:clustering, %{session: ctx.session})

      assert summary_scope == ~w(cards groups votes notes)
      assert Map.keys(summary) |> Enum.sort() == ~w(cards groups language notes title votes)a

      # Clustering is about which cards look alike, so it gets the cards and
      # nothing else — not the votes, not the notes.
      assert clustering_scope == ~w(cards)
      assert Map.keys(clustering) |> Enum.sort() == ~w(cards title)a
    end

    @tag req: ["AI-015"]
    test "the content that is needed does arrive", ctx do
      {:ok, input, _scope} = Scope.build(:session_summary, %{session: ctx.session})

      assert Enum.map(input.cards, & &1.text) |> Enum.member?("Deploys are slow")
      assert [%{label: "Tooling"}] = input.groups
      assert [%{body: "Fix the build first"}] = input.notes
      assert Enum.any?(input.votes, &(&1.votes == 1))
    end

    @tag req: ["AI-015"]
    test "and a request with nothing to work on is refused", ctx do
      assert Scope.build(:translation, %{text: ""}) == {:error, :not_found}
      assert Scope.build(:session_summary, %{team: ctx.team}) == {:error, :not_found}
    end

    @tag req: ["AI-017"]
    test "the size of what was sent is recorded, and nothing else about it", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      assert suggestion.input_bytes ==
               Scope.size(elem(Scope.build(:session_summary, %{session: ctx.session}), 1))

      refute suggestion.output
    end
  end

  describe "what the operations log says (AI-017)" do
    setup ctx do
      # The suite runs at `:warning` so the output stays readable; this one
      # is about what the log says, so it has to be listening.
      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)

      Map.merge(ctx, played(ctx))
    end

    @tag req: ["AI-017"]
    test "type, timing, size and outcome — and nothing anybody wrote", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      attach_telemetry()

      log = capture_log(fn -> run(suggestion) end)

      # What an operator gets: which kind of job, how long it took, how much
      # was sent, and whether it worked.
      assert_receive {:ai_job, measurements, metadata}
      assert metadata.type == "session_summary"
      assert metadata.outcome == "ok"
      assert measurements.duration >= 0
      assert measurements.input_bytes > 0

      # AI-017: "logged with content redacted". A retrospective is not an
      # operational concern.
      assert log =~ "ai job finished"
      refute log =~ "Deploys are slow"
      refute log =~ "Fix the build first"
      refute log =~ "## Summary"
      refute log =~ "Ploy"
    end

    @tag req: ["AI-017"]
    test "and a failure says so without saying what was in the session", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      FakeAdapter.fail(:provider_unavailable)
      attach_telemetry()

      log = capture_log(fn -> run(suggestion) end)

      assert_receive {:ai_job, _measurements, %{outcome: "error"}}
      refute log =~ "Deploys are slow"
    end
  end

  describe "the kill switch reaching a queued job (FR-806, AI-003)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-003", "FR-806"]
    test "a job queued before the switch flipped does not run", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      admin = insert(:org_admin)
      {:ok, _settings} = Admin.update_settings(admin, %{ai_enabled: false})

      assert {:cancel, :ai_disabled} =
               perform_job(Worker, %{"suggestion_id" => suggestion.id, "context" => %{}})

      assert Suggestion.status(Repo.get(Suggestion, suggestion.id)) == :failed
    end
  end

  describe "listing what has been suggested" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-005"]
    test "a team's suggestions, newest first and filterable", ctx do
      {:ok, summary} = AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})
      {:ok, clustering} = AI.request(ctx.lead, ctx.team, :clustering, %{session: ctx.session})

      assert ctx.team |> AI.list_suggestions() |> Enum.map(& &1.id) == [clustering.id, summary.id]

      assert ctx.team |> AI.list_suggestions(type: :clustering) |> Enum.map(& &1.id) ==
               [clustering.id]

      assert ctx.team |> AI.list_suggestions(status: :queued) |> length() == 2
      assert ctx.team |> AI.list_suggestions(nonsense: 1) |> length() == 2
    end

    @tag req: ["AI-005"]
    test "and one session's, by type", ctx do
      {:ok, summary} = AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})
      {:ok, _clustering} = AI.request(ctx.lead, ctx.team, :clustering, %{session: ctx.session})

      assert ctx.session
             |> AI.list_session_suggestions(:session_summary)
             |> Enum.map(& &1.id) == [summary.id]

      assert ctx.session |> AI.list_session_suggestions() |> length() == 2
    end

    @tag req: ["AI-005"]
    test "a ready suggestion is announced to whoever is watching the team", ctx do
      AI.subscribe(ctx.team.id)

      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      run(suggestion)

      assert_receive {:ai_suggestion, %{status: "ready", type: "session_summary"}}
    end
  end

  describe "retention (AI-018)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-018", "FR-804"]
    test "a purged session takes its suggestions with it", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      admin = insert(:org_admin)

      {:ok, _purged} = Admin.purge_session(admin, ctx.session)

      assert Repo.get(Suggestion, suggestion.id) == nil
    end

    @tag req: ["AI-018", "FR-804"]
    test "and a purged team takes all of them", ctx do
      {:ok, suggestion} = AI.request(ctx.lead, ctx.team, :recurring_themes, %{})
      admin = insert(:org_admin)

      {:ok, _purged} = Admin.purge_team(admin, ctx.team)

      assert Repo.get(Suggestion, suggestion.id) == nil
    end

    @tag req: ["AI-009", "FR-804"]
    test "but an accepted summary survives its suggestion being purged", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :session_summary, %{session: ctx.session})

      {:ok, _accepted} = AI.accept(ctx.lead, run(suggestion))

      Repo.delete!(Repo.get(Suggestion, suggestion.id))

      # The facilitator signed off on that text; it is part of the recap now.
      assert Repo.get(Session, ctx.session.id).summary =~ "## Summary"
    end
  end

  describe "accepting what is not a summary (AI-010, AI-011)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["AI-010", "AI-002"]
    test "a clustering suggestion writes nothing by itself", ctx do
      {:ok, suggestion} = AI.request(ctx.lead, ctx.team, :clustering, %{session: ctx.session})
      before = length(Board.list_groups(ctx.session))

      {:ok, accepted} = AI.accept(ctx.lead, run(suggestion))

      # Accepting records the decision; applying it is `Board.create_group/4`,
      # which the screen calls with the facilitator's chosen label (AI-002).
      assert Suggestion.status(accepted) == :accepted
      assert length(Board.list_groups(ctx.session)) == before
    end

    @tag req: ["AI-011", "AI-002"]
    test "and an action draft writes no action item", ctx do
      {:ok, suggestion} =
        AI.request(ctx.lead, ctx.team, :action_draft, %{session: ctx.session, topic: "Tooling"})

      {:ok, accepted} = AI.accept(ctx.member, run(suggestion))

      assert accepted.accepted_output =~ "Tooling"
      assert Actions.list_session_actions(ctx.session) == []
    end
  end
end
