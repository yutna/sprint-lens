defmodule SprintLensWeb.Api.V1.SessionApiTest do
  @moduledoc """
  The `/api/v1` session surface (§7.2).

  Asserts the same rules as the LiveView tests, on purpose: both go through
  `SprintLens.Retro`, and a permission or transition that holds on one surface
  but not the other is the drift NFR-201 exists to prevent.
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Retro
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session

  setup %{conn: conn} do
    facilitator = insert(:user, language: "en")
    team = team_with_lead(facilitator)
    participant = insert(:user, language: "en")
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

  defp create_session(ctx, attrs \\ %{}) do
    {:ok, session} =
      Retro.create_session(ctx.facilitator, ctx.team, Map.merge(%{title: "R"}, attrs))

    session
  end

  defp start_session(ctx, attrs \\ %{}) do
    {:ok, session} = Retro.start_session(ctx.facilitator, create_session(ctx, attrs))
    session
  end

  describe "GET and POST /api/v1/teams/:id/sessions" do
    @tag req: ["FR-201"]
    test "creates a session and returns its board", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/teams/#{ctx.team}/sessions", %{title: "Sprint 12"})
        |> json_response(201)

      assert body["data"]["title"] == "Sprint 12"
      assert body["data"]["state"] == "created"
      assert body["data"]["phase"] == "checkin"
      assert length(body["data"]["columns"]) == 3
      assert body["data"]["join_code"]
    end

    @tag req: ["FR-201"]
    test "accepts fields nested under session", ctx do
      assert ctx.conn
             |> post(~p"/api/v1/teams/#{ctx.team}/sessions", %{session: %{title: "Nested"}})
             |> json_response(201)
    end

    @tag req: ["FR-203"]
    test "lists a team's sessions", ctx do
      session = create_session(ctx)

      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/sessions") |> json_response(200)

      assert [%{"id" => id, "title" => "R"}] = body["data"]
      assert id == session.id
    end

    @tag req: ["FR-103"]
    test "another team's sessions are not reachable", ctx do
      theirs = team_with_lead(insert(:user))

      assert ctx.conn |> get(~p"/api/v1/teams/#{theirs}/sessions") |> json_response(404)
    end

    @tag req: ["FR-919"]
    test "an invalid vote budget is reported in the shared envelope", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/teams/#{ctx.team}/sessions", %{title: "Bad", vote_budget: 0})
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["fields"]["vote_budget"] != []
    end
  end

  describe "GET /api/v1/sessions/:id" do
    @tag req: ["FR-309"]
    test "returns the same board snapshot a realtime client gets", ctx do
      session = start_session(ctx)
      {:ok, _timed} = Retro.start_timer(ctx.facilitator, session, 300)

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}") |> json_response(200)

      assert body["data"]["timer"]["running"]
      assert body["data"]["timer"]["remaining_s"] <= 300
      assert body["data"]["facilitator"]["display_name"] == ctx.facilitator.display_name
      refute get_in(body, ["data", "facilitator", "email"])
    end

    @tag req: ["FR-103"]
    test "an outsider cannot read a board", ctx do
      session = create_session(ctx)

      assert build_conn()
             |> authed(insert(:user))
             |> get(~p"/api/v1/sessions/#{session}")
             |> json_response(404)
    end
  end

  describe "POST /api/v1/sessions/join" do
    @tag req: ["FR-204"]
    test "resolves a join code", ctx do
      session = start_session(ctx)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/join", %{code: String.downcase(session.join_code)})
        |> json_response(200)

      assert body["data"]["id"] == session.id
    end

    @tag req: ["FR-919"]
    test "an id that is not a number is not found rather than a crash", ctx do
      # A path segment is whatever a stranger typed. Letting Ecto raise on it
      # turns a mistyped link into a 500 and a stack trace in the logs.
      body = ctx.conn |> get(~p"/api/v1/sessions/not-a-number") |> json_response(404)

      assert body["error"]["code"] == "not_found"
    end

    @tag req: ["FR-204"]
    test "an unknown code is not found", ctx do
      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/join", %{code: "ZZZZZZ"})
             |> json_response(404)
    end

    @tag req: ["FR-205"]
    test "a closed session says so", ctx do
      {:ok, closed} = Retro.close_session(ctx.facilitator, start_session(ctx))

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/join", %{code: closed.join_code})
        |> json_response(422)

      assert body["error"]["code"] == "session_closed"
    end
  end

  describe "POST /api/v1/sessions/:id/phase" do
    @tag req: ["FR-205"]
    test "starts and closes the session", ctx do
      session = create_session(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "start"})
        |> json_response(200)

      assert body["data"]["state"] == "active"

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "close"})
        |> json_response(200)

      assert body["data"]["state"] == "closed"
    end

    @tag req: ["FR-206"]
    test "advances and reverts", ctx do
      session = start_session(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "advance"})
             |> json_response(200)
             |> get_in(["data", "phase"]) == "brainstorm"

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "revert"})
             |> json_response(200)
             |> get_in(["data", "phase"]) == "checkin"
    end

    @tag req: ["FR-206"]
    test "jumps to a named phase, which is how one is skipped", ctx do
      session = start_session(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{phase: "vote"})
             |> json_response(200)
             |> get_in(["data", "phase"]) == "vote"
    end

    @tag req: ["FR-206", "NFR-102"]
    test "an API change reaches the realtime clients too", ctx do
      session = start_session(ctx)
      Events.subscribe(session.id)

      ctx.conn |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "advance"})

      assert_receive {:retro_event, "phase.changed", %{phase: :brainstorm}}
    end

    @tag req: ["FR-919"]
    test "an unrecognised action or phase is refused", ctx do
      session = start_session(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "teleport"})
             |> json_response(422)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{phase: "nonsense"})
             |> json_response(422)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{})
             |> json_response(422)

      # A phase sent as something other than a string, which a sloppy client
      # will eventually do.
      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{phase: 3})
             |> json_response(422)
    end

    @tag req: ["NFR-201"]
    test "a participant cannot change the phase over the API either", ctx do
      session = start_session(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/phase", %{action: "advance"})
             |> json_response(403)
    end
  end

  describe "POST /api/v1/sessions/:id/timer" do
    @tag req: ["FR-208"]
    test "starts, pauses and resets", ctx do
      session = start_session(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/timer", %{action: "start", duration_s: 300})
        |> json_response(200)

      assert body["data"]["timer"]["running"]

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/timer", %{action: "pause"})
        |> json_response(200)

      refute body["data"]["timer"]["running"]

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/timer", %{action: "reset"})
        |> json_response(200)

      assert body["data"]["timer"]["remaining_s"] == nil
    end

    @tag req: ["FR-919"]
    test "an unrecognised action is refused", ctx do
      session = start_session(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/timer", %{action: "explode"})
             |> json_response(422)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/timer", %{})
             |> json_response(422)
    end

    @tag req: ["NFR-201"]
    test "a participant cannot touch the timer", ctx do
      session = start_session(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/timer", %{action: "start", duration_s: 60})
             |> json_response(403)
    end
  end

  describe "POST /api/v1/sessions/:id/facilitator" do
    @tag req: ["FR-207"]
    test "hands the role to another member", ctx do
      session = start_session(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/facilitator", %{user_id: ctx.participant.id})
        |> json_response(200)

      assert body["data"]["facilitator"]["id"] == ctx.participant.id
    end

    @tag req: ["FR-207"]
    test "refuses someone outside the team", ctx do
      session = start_session(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/facilitator", %{user_id: insert(:user).id})
             |> json_response(404)
    end

    @tag req: ["NFR-201"]
    test "a participant cannot take the role", ctx do
      session = start_session(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/facilitator", %{user_id: ctx.participant.id})
             |> json_response(403)
    end
  end

  describe "the session summary" do
    @tag req: ["FR-203"]
    test "a listed session does not leak the join code", ctx do
      start_session(ctx)

      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/sessions") |> json_response(200)

      refute Map.has_key?(hd(body["data"]), "join_code")
    end

    @tag req: ["FR-210"]
    test "reports the modes a client must respect", ctx do
      session = create_session(ctx, %{is_anonymous: true, is_blind: true})

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}") |> json_response(200)

      assert body["data"]["is_anonymous"]
      assert body["data"]["is_blind"]
      refute body["data"]["cards_revealed"]
    end

    @tag req: ["FR-205"]
    test "a closed session carries when it closed", ctx do
      {:ok, closed} = Retro.close_session(ctx.facilitator, start_session(ctx))

      body = ctx.conn |> get(~p"/api/v1/sessions/#{closed}") |> json_response(200)

      assert body["data"]["closed_at"]
      assert Session.state(closed) == :closed
    end
  end
end
