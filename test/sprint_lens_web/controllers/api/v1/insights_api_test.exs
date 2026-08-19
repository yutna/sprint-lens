defmodule SprintLensWeb.Api.V1.InsightsApiTest do
  @moduledoc """
  The `/api/v1` history and insights surface (§7.2).

  Every promise the screens make has to hold here too, and the two that would
  hurt most if they did not are search reaching into a live session (FR-209)
  and the org-wide view carrying somebody's words (FR-605).
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Retro.Board

  setup %{conn: conn} do
    facilitator = insert(:user, language: "en", display_name: "Lek")
    team = team_with_lead(facilitator)
    participant = insert(:user, language: "en", display_name: "Ploy")
    join_team(participant, team)

    %{
      conn: authed(conn, facilitator),
      participant_conn: authed(conn, participant),
      team: team,
      facilitator: facilitator,
      participant: participant
    }
  end

  defp authed(conn, user) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> Accounts.create_api_token(user))
  end

  defp played(ctx, attrs \\ %{}) do
    {:ok, session} =
      Retro.create_session(ctx.facilitator, ctx.team, Map.merge(%{title: "Sprint 12"}, attrs))

    {:ok, session} = Retro.start_session(ctx.facilitator, session)
    {:ok, _mood} = Board.record_mood(ctx.participant, session, :checkin_mood, 4)
    {:ok, _mood} = Board.record_mood(ctx.facilitator, session, :checkin_mood, 4)

    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    {:ok, card} =
      Board.create_card(ctx.participant, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, voting} = Retro.set_phase(ctx.facilitator, session, :vote)
    {:ok, _vote} = Board.cast_vote(ctx.participant, voting, {:card, card.id})

    {:ok, discussing} = Retro.set_phase(ctx.facilitator, voting, :discuss)

    {:ok, _note} =
      Board.write_note(ctx.facilitator, discussing, {:card, card.id}, "Fix the build first")

    {:ok, action} =
      Actions.create_action(ctx.participant, discussing, %{title: "Write the runbook"})

    {:ok, closed} = Retro.close_session(ctx.facilitator, discussing)

    %{session: closed, card: card, action: action}
  end

  describe "GET /api/v1/teams/:id/archive" do
    @tag req: ["FR-601"]
    test "lists what has finished, with how it went", ctx do
      %{session: closed} = played(ctx)

      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/archive") |> json_response(200)

      assert [entry] = body["data"]
      assert entry["session_id"] == closed.id
      assert entry["title"] == "Sprint 12"
      assert entry["participant_count"] == 2
      assert entry["card_count"] == 1
      assert entry["mood_average"] == 4.0
      assert entry["closed_at"]
    end

    @tag req: ["FR-601"]
    test "and nothing that is still running", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "Live"})
      {:ok, _started} = Retro.start_session(ctx.facilitator, session)

      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/archive") |> json_response(200)

      assert body["data"] == []
    end

    @tag req: ["FR-103"]
    test "a team you are not in has no archive", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger |> get(~p"/api/v1/teams/#{ctx.team}/archive") |> json_response(404)
    end
  end

  describe "GET /api/v1/sessions/:id/recap" do
    @tag req: ["FR-602"]
    test "carries the board, the discussion and what was agreed", ctx do
      %{session: closed, card: card, action: action} = played(ctx)

      body =
        ctx.participant_conn
        |> get(~p"/api/v1/sessions/#{closed}/recap")
        |> json_response(200)

      data = body["data"]

      assert data["session_id"] == closed.id
      assert data["participant_count"] == 2
      assert length(data["columns"]) == 3
      assert [%{"id" => card_id, "text" => "Deploys are slow"}] = data["cards"]
      assert card_id == card.id
      assert [topic] = data["topics"]
      assert topic["votes"] == 1
      assert topic["note"] == "Fix the build first"
      assert [%{"id" => action_id}] = data["actions"]
      assert action_id == action.id
      assert data["mood"]["average"] == 4.0
    end

    @tag req: ["FR-210", "FR-602"]
    test "an anonymous session's recap names nobody", ctx do
      %{session: closed} = played(ctx, %{is_anonymous: true})

      body = ctx.conn |> get(~p"/api/v1/sessions/#{closed}/recap") |> json_response(200)

      assert [card] = body["data"]["cards"]
      refute Map.has_key?(card, "author")
      refute body |> Jason.encode!() |> String.contains?("Ploy")
    end

    @tag req: ["FR-602"]
    test "a session still running has no recap", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "Live"})
      {:ok, started} = Retro.start_session(ctx.facilitator, session)

      assert ctx.conn |> get(~p"/api/v1/sessions/#{started}/recap") |> json_response(404)
    end
  end

  describe "GET /api/v1/teams/:id/search" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-603"]
    test "finds cards, notes and actions", ctx do
      body =
        ctx.participant_conn
        |> get(~p"/api/v1/teams/#{ctx.team}/search?q=the")
        |> json_response(200)

      assert body["data"]["query"] == "the"
      assert [note] = body["data"]["notes"]
      assert note["body"] == "Fix the build first"
      assert [action] = body["data"]["actions"]
      assert action["title"] == "Write the runbook"
    end

    @tag req: ["FR-603"]
    test "a found card says which session and column it was in", ctx do
      body =
        ctx.participant_conn
        |> get(~p"/api/v1/teams/#{ctx.team}/search?q=deploys")
        |> json_response(200)

      assert [card] = body["data"]["cards"]
      assert card["id"] == ctx.card.id
      assert card["session_id"] == ctx.session.id
      assert card["session_title"] == "Sprint 12"
      assert card["column_name"]
    end

    @tag req: ["FR-209", "FR-603"]
    test "and never reaches into a session that is still running", ctx do
      {:ok, live} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "L", is_blind: true})
      {:ok, live} = Retro.start_session(ctx.facilitator, live)
      {:ok, live} = Retro.set_phase(ctx.facilitator, live, :brainstorm)

      {:ok, _secret} =
        Board.create_card(ctx.facilitator, live, %{
          column_id: hd(live.columns).id,
          text: "Deploys are secretly worse"
        })

      body =
        ctx.participant_conn
        |> get(~p"/api/v1/teams/#{ctx.team}/search?q=deploys")
        |> json_response(200)

      assert length(body["data"]["cards"]) == 1
      refute body |> Jason.encode!() |> String.contains?("secretly")
    end

    @tag req: ["FR-603"]
    test "a wildcard is a character, not a wildcard", ctx do
      body =
        ctx.participant_conn
        |> get(~p"/api/v1/teams/#{ctx.team}/search?q=%25")
        |> json_response(200)

      assert body["data"]["cards"] == []
    end

    @tag req: ["FR-603"]
    test "an empty search is refused rather than answered with everything", ctx do
      assert ctx.participant_conn
             |> get(~p"/api/v1/teams/#{ctx.team}/search")
             |> json_response(422)
    end

    @tag req: ["FR-103"]
    test "and a stranger searches nothing", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger
             |> get(~p"/api/v1/teams/#{ctx.team}/search?q=deploys")
             |> json_response(404)
    end
  end

  describe "GET /api/v1/teams/:id/insights" do
    @tag req: ["FR-604"]
    test "a point per finished session, oldest first", ctx do
      %{session: first} = played(ctx)
      %{session: second} = played(ctx)

      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/insights") |> json_response(200)
      data = body["data"]

      assert data["session_count"] == 2
      assert Enum.map(data["mood_trend"], & &1["session_id"]) == [first.id, second.id]
      assert Enum.map(data["mood_trend"], & &1["value"]) == [4.0, 4.0]
      assert Enum.map(data["participation"], & &1["value"]) == [100.0, 100.0]
      assert data["actions"]["open_count"] == 2
    end

    @tag req: ["FR-103"]
    test "and a team you are not in has none", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger |> get(~p"/api/v1/teams/#{ctx.team}/insights") |> json_response(404)
    end
  end

  describe "GET /api/v1/insights/org" do
    @tag req: ["FR-605"]
    test "an Org Admin gets aggregates per team", %{conn: conn} = ctx do
      played(ctx)
      admin = authed(conn, insert(:org_admin, language: "en"))

      body = admin |> get(~p"/api/v1/insights/org") |> json_response(200)

      row = Enum.find(body["data"]["teams"], &(&1["team_id"] == ctx.team.id))

      assert row["session_count"] == 1
      assert row["mood_average"] == 4.0
      assert body["data"]["totals"]["open_actions"] >= 1
    end

    @tag req: ["FR-605", "FR-606"]
    test "and nothing anybody wrote, nor anybody's name", %{conn: conn} = ctx do
      played(ctx)
      admin = authed(conn, insert(:org_admin, language: "en"))

      body = admin |> get(~p"/api/v1/insights/org") |> json_response(200)
      encoded = Jason.encode!(body)

      refute encoded =~ "Deploys are slow"
      refute encoded =~ "Fix the build first"
      refute encoded =~ "Write the runbook"
      refute encoded =~ "Ploy"
      refute encoded =~ "Lek"
    end

    @tag req: ["FR-605"]
    test "and nobody else may ask", ctx do
      assert ctx.conn |> get(~p"/api/v1/insights/org") |> json_response(403)
    end
  end
end
