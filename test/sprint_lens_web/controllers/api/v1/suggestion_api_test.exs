defmodule SprintLensWeb.Api.V1.SuggestionApiTest do
  @moduledoc """
  The `/api/v1` suggestion surface (§7.2, §5.2).

  The envelope is checked field for field against §5.2, and the gates are
  checked the same way every other surface's are: the API is not a way round
  a switch somebody turned off.
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Admin
  alias SprintLens.AI
  alias SprintLens.AI.FakeAdapter
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLens.Workers.AiSuggestion, as: Worker

  setup %{conn: conn} do
    facilitator = insert(:user, language: "en", display_name: "Lek")
    team = team_with_lead(facilitator)
    member = insert(:user, language: "en", display_name: "Ploy")
    join_team(member, team)

    {:ok, team} = Teams.update_team_settings(facilitator, team, %{ai_opt_in: true})

    %{
      conn: authed(conn, facilitator),
      member_conn: authed(conn, member),
      team: team,
      facilitator: facilitator,
      member: member
    }
  end

  defp authed(conn, user) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> Accounts.create_api_token(user))
  end

  defp closed_session(ctx) do
    {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "Sprint 12"})
    {:ok, session} = Retro.start_session(ctx.facilitator, session)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    {:ok, _card} =
      Board.create_card(ctx.member, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, closed} = Retro.close_session(ctx.facilitator, session)

    %{session: closed}
  end

  defp run_jobs do
    for job <- Repo.all(Oban.Job), do: perform_job(Worker, job.args)
  end

  describe "POST /api/v1/sessions/:id/suggestions" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["AI-005"]
    test "asks, and answers straight away with a queued envelope", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.session}/suggestions", %{type: "session_summary"})
        |> json_response(202)

      data = body["data"]

      # §5.2's envelope, field for field.
      assert data["type"] == "session_summary"
      assert data["status"] == "queued"
      assert data["team_id"] == ctx.team.id
      assert data["session_id"] == ctx.session.id
      assert data["input_scope"] == ~w(cards groups votes notes)
      assert data["output"] == nil
      assert data["created_at"]
    end

    @tag req: ["AI-005"]
    test "a type nobody offers is refused, with the ones that exist", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.session}/suggestions", %{type: "horoscope"})
        |> json_response(422)

      assert body["error"]["details"]["type"] == [
               "session_summary",
               "clustering",
               "action_draft",
               "recurring_themes",
               "icebreakers",
               "translation"
             ]
    end

    @tag req: ["AI-003"]
    test "and a team that has not opted in gets nothing", ctx do
      {:ok, _opted_out} =
        Teams.update_team_settings(ctx.facilitator, ctx.team, %{ai_opt_in: false})

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.session}/suggestions", %{type: "session_summary"})
        |> json_response(422)

      assert body["error"]["code"] == "ai_disabled"
    end

    @tag req: ["FR-806", "AI-003"]
    test "nor does anybody while the kill switch is on", ctx do
      {:ok, _settings} = Admin.update_settings(insert(:org_admin), %{ai_enabled: false})

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{ctx.session}/suggestions", %{type: "session_summary"})
             |> json_response(422)
    end

    @tag req: ["FR-103"]
    test "and a stranger asks for nothing", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger
             |> post(~p"/api/v1/sessions/#{ctx.session}/suggestions", %{type: "session_summary"})
             |> json_response(404)
    end

    @tag req: ["AI-011"]
    test "the extras a feature needs come through the body", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.session}/suggestions", %{
          type: "action_draft",
          topic: "Deploys",
          note: "Cache the layers",
          language: "en"
        })
        |> json_response(202)

      run_jobs()

      {:ok, suggestion} = AI.fetch_suggestion(ctx.facilitator, body["data"]["id"])
      assert suggestion.output =~ "Deploys"
    end
  end

  describe "GET /api/v1/suggestions/:id" do
    setup ctx do
      state = closed_session(ctx)

      {:ok, suggestion} =
        AI.request(ctx.facilitator, ctx.team, :session_summary, %{session: state.session})

      Map.merge(ctx, Map.put(state, :suggestion, suggestion))
    end

    @tag req: ["AI-005"]
    test "polls until the output arrives", ctx do
      body = ctx.conn |> get(~p"/api/v1/suggestions/#{ctx.suggestion}") |> json_response(200)
      assert body["data"]["status"] == "queued"
      assert body["data"]["output"] == nil

      run_jobs()

      body = ctx.conn |> get(~p"/api/v1/suggestions/#{ctx.suggestion}") |> json_response(200)

      assert body["data"]["status"] == "ready"
      assert body["data"]["output"]["format"] == "markdown"
      assert body["data"]["output"]["content"] =~ "## Summary"
    end

    @tag req: ["AI-010"]
    test "a clustering suggestion comes back as JSON, per §5.2", ctx do
      {:ok, clustering} =
        AI.request(ctx.facilitator, ctx.team, :clustering, %{session: ctx.session})

      run_jobs()

      body = ctx.conn |> get(~p"/api/v1/suggestions/#{clustering}") |> json_response(200)

      assert body["data"]["output"]["format"] == "json"
      assert %{"groups" => [_group]} = Jason.decode!(body["data"]["output"]["content"])
    end

    @tag req: ["AI-014"]
    test "a translation is marked as machine translated", ctx do
      {:ok, translation} =
        AI.request(ctx.facilitator, ctx.team, :translation, %{text: "สวัสดี", language: "en"})

      run_jobs()

      body = ctx.conn |> get(~p"/api/v1/suggestions/#{translation}") |> json_response(200)

      assert body["data"]["machine_translated"]

      summary = ctx.conn |> get(~p"/api/v1/suggestions/#{ctx.suggestion}") |> json_response(200)
      refute summary["data"]["machine_translated"]
    end

    @tag req: ["AI-006"]
    test "and says so when the job failed", ctx do
      FakeAdapter.fail(:provider_unavailable)
      run_jobs()

      body = ctx.conn |> get(~p"/api/v1/suggestions/#{ctx.suggestion}") |> json_response(200)

      assert body["data"]["status"] == "failed"
      assert body["data"]["error"] =~ "provider_unavailable"
    end

    @tag req: ["FR-103"]
    test "a suggestion belonging to another team is not found", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger |> get(~p"/api/v1/suggestions/#{ctx.suggestion}") |> json_response(404)
      assert ctx.conn |> get(~p"/api/v1/suggestions/0") |> json_response(404)
    end
  end

  describe "PATCH /api/v1/suggestions/:id (AI-002)" do
    setup ctx do
      state = closed_session(ctx)

      {:ok, suggestion} =
        AI.request(ctx.facilitator, ctx.team, :session_summary, %{session: state.session})

      run_jobs()

      Map.merge(ctx, Map.put(state, :suggestion, suggestion))
    end

    @tag req: ["AI-002", "AI-009"]
    test "accepting attaches the summary to the session", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "accept"})
        |> json_response(200)

      assert body["data"]["status"] == "accepted"
      assert Repo.get(Session, ctx.session.id).summary =~ "## Summary"
    end

    @tag req: ["AI-002"]
    test "accepting an edited version keeps the human's words", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{
          action: "accept",
          output: "## Ours\n\nShip it."
        })
        |> json_response(200)

      assert body["data"]["output"]["content"] == "## Ours\n\nShip it."
      assert Repo.get(Session, ctx.session.id).summary == "## Ours\n\nShip it."
    end

    @tag req: ["AI-002"]
    test "rejecting attaches nothing", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "reject"})
        |> json_response(200)

      assert body["data"]["status"] == "rejected"
      assert Repo.get(Session, ctx.session.id).summary == nil
    end

    @tag req: ["AI-006"]
    test "retrying makes a new one", ctx do
      ctx.conn
      |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "reject"})
      |> json_response(200)

      body =
        ctx.conn
        |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "retry"})
        |> json_response(200)

      refute body["data"]["id"] == ctx.suggestion.id
      assert body["data"]["status"] == "queued"
    end

    @tag req: ["AI-002"]
    test "an action nobody offers is refused, with the ones that exist", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "apply"})
        |> json_response(422)

      assert body["error"]["details"]["action"] == ["accept", "reject", "retry"]
    end

    @tag req: ["AI-002"]
    test "and a decision is made once", ctx do
      ctx.conn
      |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "accept"})
      |> json_response(200)

      body =
        ctx.conn
        |> patch(~p"/api/v1/suggestions/#{ctx.suggestion}", %{action: "accept"})
        |> json_response(422)

      assert body["error"]["code"] == "wrong_state"
    end
  end
end
