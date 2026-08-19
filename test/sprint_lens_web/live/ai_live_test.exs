defmodule SprintLensWeb.AILiveTest do
  @moduledoc """
  The suggestion slot on screen (AI-001, AI-002, AI-006, scenario 10.6).

  Two halves of scenario 10.6 live here: a summary that reaches the recap
  only after somebody says yes, and a session with AI switched off where no
  control appears at all.
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Admin
  alias SprintLens.AI
  alias SprintLens.AI.FakeAdapter
  alias SprintLens.AI.Suggestion
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer
  alias SprintLens.Teams
  alias SprintLens.Workers.AiSuggestion, as: Worker

  setup :register_and_log_in_user

  setup %{user: user} do
    team = team_with_lead(user)
    member = insert(:user, language: "en", display_name: "Ploy")
    join_team(member, team)

    {:ok, team} = Teams.update_team_settings(user, team, %{ai_opt_in: true})

    %{
      team: team,
      facilitator: user,
      member: member,
      member_conn: log_in_user(build_conn(), member)
    }
  end

  defp closed_session(ctx) do
    session = active_session(ctx.team, ctx.facilitator)
    on_exit(fn -> SessionServer.stop(session.id) end)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    {:ok, _card} =
      Board.create_card(ctx.member, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, closed} = Retro.close_session(ctx.facilitator, session)

    %{session: closed}
  end

  defp run_queued_jobs do
    for job <- Repo.all(Oban.Job) do
      perform_job(Worker, job.args)
    end
  end

  describe "asking for a summary (AI-005, AI-009)" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["AI-005"]
    test "the slot is there, and asking queues a job", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      assert has_element?(lv, "#ai-summary-request")

      lv |> element("#ai-summary-request") |> render_click()

      assert has_element?(lv, "#ai-summary-working")
      assert [suggestion] = AI.list_session_suggestions(ctx.session)
      assert Suggestion.status(suggestion) == :queued
    end

    @tag req: ["AI-005", "AI-002"]
    test "and the draft appears when the job finishes, applied to nothing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      lv |> element("#ai-summary-request") |> render_click()
      run_queued_jobs()

      assert render(lv) =~ "## Summary"
      assert has_element?(lv, "#ai-summary-accept")

      # AI-002: nothing is applied automatically. The recap has no summary
      # until somebody says so.
      refute has_element?(lv, "#recap-summary-text")
      assert %Session{summary: nil} = Repo.get(Session, ctx.session.id)
    end
  end

  describe "the human's yes (AI-002, scenario 10.6)" do
    setup ctx do
      state = closed_session(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{state.session}/recap")

      lv |> element("#ai-summary-request") |> render_click()
      run_queued_jobs()

      Map.merge(ctx, Map.put(state, :lv, lv))
    end

    @tag req: ["AI-002", "AI-009"]
    test "@spec-10.6 accepting attaches it to the recap", ctx do
      ctx.lv |> element("#ai-summary-accept") |> render_click()

      assert has_element?(ctx.lv, "#recap-summary-text", "## Summary")
      assert has_element?(ctx.lv, "#ai-summary-accepted")
      assert Repo.get(Session, ctx.session.id).summary =~ "## Summary"
    end

    @tag req: ["AI-002"]
    test "editing first keeps the human's words", ctx do
      ctx.lv |> element("#ai-summary-edit") |> render_click()

      assert has_element?(ctx.lv, "#ai-summary-editor")

      ctx.lv
      |> form("#ai-summary-form", suggestion: %{output: "## What we agreed\n\nShip it."})
      |> render_submit()

      assert has_element?(ctx.lv, "#recap-summary-text", "Ship it.")
      assert Repo.get(Session, ctx.session.id).summary == "## What we agreed\n\nShip it."
    end

    @tag req: ["AI-002"]
    test "and editing can be abandoned", ctx do
      ctx.lv |> element("#ai-summary-edit") |> render_click()
      ctx.lv |> element("#ai-summary-cancel") |> render_click()

      refute has_element?(ctx.lv, "#ai-summary-editor")
      assert has_element?(ctx.lv, "#ai-summary-accept")
    end

    @tag req: ["AI-002"]
    test "rejecting attaches nothing and offers another go", ctx do
      ctx.lv |> element("#ai-summary-reject") |> render_click()

      assert has_element?(ctx.lv, "#ai-summary-rejected")
      assert has_element?(ctx.lv, "#ai-summary-request")
      assert %Session{summary: nil} = Repo.get(Session, ctx.session.id)
    end
  end

  describe "when the assistant does not answer (AI-006)" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["AI-006"]
    test "the slot says so and offers a retry, and the recap still works", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      lv |> element("#ai-summary-request") |> render_click()
      FakeAdapter.fail()
      run_queued_jobs()

      assert has_element?(lv, "#ai-summary-failed")
      assert has_element?(lv, "#ai-summary-retry")

      # AI-006: "the core flow continues".
      assert has_element?(lv, "#recap-board", "Deploys are slow")

      FakeAdapter.succeed()
      lv |> element("#ai-summary-retry") |> render_click()
      run_queued_jobs()

      assert has_element?(lv, "#ai-summary-accept")
    end
  end

  describe "when AI is switched off (AI-001, AI-003, scenario 10.6)" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["AI-001", "AI-003"]
    test "@spec-10.6 a team that never opted in sees no AI control at all", ctx do
      {:ok, _opted_out} =
        Teams.update_team_settings(ctx.facilitator, ctx.team, %{ai_opt_in: false})

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      refute has_element?(lv, "#ai-summary")

      # And everything else on the page is exactly as it was (AI-001).
      assert has_element?(lv, "#recap-board", "Deploys are slow")
      assert has_element?(lv, "#recap-participants")
      assert has_element?(lv, "#export-markdown")
    end

    @tag req: ["AI-001", "FR-806"]
    test "@spec-10.6 nor does anybody when the kill switch is on", ctx do
      admin = insert(:org_admin, language: "en")
      {:ok, _settings} = Admin.update_settings(admin, %{ai_enabled: false})

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      refute has_element?(lv, "#ai-summary")
      assert has_element?(lv, "#recap-board", "Deploys are slow")
    end

    @tag req: ["NFR-201", "AI-003"]
    test "and a forged request is refused", ctx do
      admin = insert(:org_admin, language: "en")
      {:ok, _settings} = Admin.update_settings(admin, %{ai_enabled: false})

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      assert render_click(lv, "request_suggestion", %{"type" => "session_summary"}) =~
               "turned off"

      assert AI.list_session_suggestions(ctx.session) == []
    end
  end

  describe "a recap that goes away underneath somebody (FR-804)" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["FR-804"]
    test "a purge while the page is open leaves it as it was rather than crashing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      {:ok, _purged} = Admin.purge_session(insert(:org_admin), ctx.session)

      # An event arrives for a session that is no longer there. The socket
      # keeps the last thing it knew rather than raising at somebody who was
      # only reading (FR-919).
      send(lv.pid, {:ai_suggestion, %{status: "ready"}})

      assert render(lv) =~ "Deploys are slow"
    end
  end

  describe "who decides (AI-002)" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["AI-009"]
    test "a participant is not offered the summary slot", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/sessions/#{ctx.session}/recap")

      # AI-009 says the draft is "for facilitator review".
      refute has_element?(lv, "#ai-summary")
    end

    @tag req: ["NFR-201"]
    test "and a suggestion from another team cannot be decided", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}/recap")

      assert render_click(lv, "accept_suggestion", %{"id" => "0"}) =~ "does not exist"
      assert render_click(lv, "reject_suggestion", %{"id" => "0"}) =~ "does not exist"
      assert render_click(lv, "retry_suggestion", %{"id" => "0"}) =~ "does not exist"
    end
  end
end
