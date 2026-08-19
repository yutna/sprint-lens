defmodule SprintLensWeb.Api.V1.ActionApiTest do
  @moduledoc """
  The `/api/v1` action surface (§7.2).

  The asymmetry these tests pin down is the one FR-501 and FR-503 create
  between them: creating goes through a live session in its discussion, while
  updating goes through the item alone and keeps working long after the
  session has closed.
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Actions
  alias SprintLens.Retro

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

  defp discussing(ctx) do
    {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
    {:ok, session} = Retro.start_session(ctx.facilitator, session)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :discuss)

    session
  end

  defp checking_in(ctx) do
    {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "Next"})
    {:ok, session} = Retro.start_session(ctx.facilitator, session)

    session
  end

  defp write(conn, session, attrs) do
    conn
    |> post(~p"/api/v1/sessions/#{session}/actions", attrs)
    |> json_response(201)
    |> Map.fetch!("data")
  end

  describe "POST /api/v1/sessions/:id/actions" do
    @tag req: ["FR-501"]
    test "writes down what the team agreed", ctx do
      session = discussing(ctx)

      item = write(ctx.participant_conn, session, %{title: "Fix the deploy script"})

      assert item["title"] == "Fix the deploy script"
      assert item["status"] == "open"
      assert item["session_id"] == session.id
      assert item["team_id"] == ctx.team.id
      assert item["assignee"] == nil
      assert item["carried_from_id"] == nil
    end

    @tag req: ["FR-502"]
    test "with an owner and a due date", ctx do
      session = discussing(ctx)

      item =
        write(ctx.participant_conn, session, %{
          title: "Fix it",
          assignee_id: ctx.facilitator.id,
          due_date: "2026-09-30",
          description: "Ask the platform team"
        })

      assert item["assignee"]["id"] == ctx.facilitator.id
      assert item["description"] == "Ask the platform team"
      assert item["due_date"] =~ "2026-09-30"
    end

    @tag req: ["FR-502"]
    test "accepts fields nested under action", ctx do
      session = discussing(ctx)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/actions", %{action: %{title: "Nested"}})
        |> json_response(201)

      assert body["data"]["title"] == "Nested"
    end

    @tag req: ["FR-502"]
    test "an owner outside the team is refused", ctx do
      session = discussing(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/actions", %{
               title: "x",
               assignee_id: insert(:user).id
             })
             |> json_response(404)
    end

    @tag req: ["FR-502"]
    test "an untitled action is refused", ctx do
      session = discussing(ctx)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/actions", %{title: "  "})
        |> json_response(422)

      assert body["error"]["details"]["fields"]["title"]
    end

    @tag req: ["FR-501"]
    test "links to a topic given either way", ctx do
      session = discussing(ctx)
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

      {:ok, card} =
        Retro.Board.create_card(ctx.participant, brainstorming, %{
          column_id: hd(session.columns).id,
          text: "Deploys are slow"
        })

      {:ok, session} = Retro.set_phase(ctx.facilitator, brainstorming, :discuss)

      by_id = write(ctx.participant_conn, session, %{title: "By id", card_id: card.id})
      by_key = write(ctx.participant_conn, session, %{title: "By key", topic: "card:#{card.id}"})

      assert by_id["card_id"] == card.id
      assert by_key["card_id"] == card.id
    end

    @tag req: ["FR-501"]
    test "a topic that is not a topic is refused", ctx do
      session = discussing(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/actions", %{title: "x", topic: "nonsense"})
             |> json_response(404)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/actions", %{title: "x", card_id: 0})
             |> json_response(404)
    end

    @tag req: ["FR-501"]
    test "actions belong to the end of the retro", ctx do
      session = discussing(ctx)
      {:ok, voting} = Retro.set_phase(ctx.facilitator, session, :vote)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{voting}/actions", %{title: "early"})
        |> json_response(422)

      assert body["error"]["code"] == "wrong_phase"
    end

    @tag req: ["FR-501"]
    test "a repeated request id creates one (§7.5)", ctx do
      session = discussing(ctx)
      params = %{title: "Once", client_request_id: "a-1"}

      first = write(ctx.participant_conn, session, params)
      again = write(ctx.participant_conn, session, params)

      assert first["id"] == again["id"]
    end

    @tag req: ["FR-103"]
    test "a stranger writes nothing", %{conn: conn} = ctx do
      session = discussing(ctx)
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger
             |> post(~p"/api/v1/sessions/#{session}/actions", %{title: "no"})
             |> json_response(404)
    end
  end

  describe "GET /api/v1/teams/:id/actions" do
    setup ctx do
      session = discussing(ctx)
      other = discussing(ctx)

      mine =
        write(ctx.participant_conn, session, %{title: "Mine", assignee_id: ctx.participant.id})

      theirs = write(ctx.participant_conn, session, %{title: "Theirs"})
      elsewhere = write(ctx.participant_conn, other, %{title: "Elsewhere"})

      ctx.conn
      |> patch(~p"/api/v1/actions/#{theirs["id"]}", %{status: "done"})
      |> json_response(200)

      Map.merge(ctx, %{
        session: session,
        other: other,
        mine: mine,
        theirs: theirs,
        elsewhere: elsewhere
      })
    end

    defp titles(body), do: body["data"] |> Enum.map(& &1["title"]) |> Enum.sort()

    @tag req: ["FR-504"]
    test "everything the team owns, with how it is doing", ctx do
      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/actions") |> json_response(200)

      assert titles(body) == ["Elsewhere", "Mine", "Theirs"]
      assert body["meta"]["open_count"] == 2
      assert body["meta"]["completion_rate"] == 33.3
    end

    @tag req: ["FR-504"]
    test "filtered by status, by owner and by session", ctx do
      by_status =
        ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/actions?status=done") |> json_response(200)

      assert titles(by_status) == ["Theirs"]

      by_owner =
        ctx.conn
        |> get(~p"/api/v1/teams/#{ctx.team}/actions?assignee_id=#{ctx.participant.id}")
        |> json_response(200)

      assert titles(by_owner) == ["Mine"]

      by_session =
        ctx.conn
        |> get(~p"/api/v1/teams/#{ctx.team}/actions?session_id=#{ctx.other.id}")
        |> json_response(200)

      assert titles(by_session) == ["Elsewhere"]
    end

    @tag req: ["FR-504"]
    test "an unknown parameter does not silently narrow the list", ctx do
      body =
        ctx.conn
        |> get(~p"/api/v1/teams/#{ctx.team}/actions?nonsense=1&status=")
        |> json_response(200)

      assert length(body["data"]) == 3
    end

    @tag req: ["FR-505"]
    test "the open list leaves out what has been superseded", ctx do
      next = checking_in(ctx)

      ctx.conn
      |> post(~p"/api/v1/sessions/#{next}/actions/#{ctx.mine["id"]}/carry-over")
      |> json_response(201)

      open = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/actions/open") |> json_response(200)
      all = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/actions") |> json_response(200)

      # The carried copy stands in for the original in the open list; the full
      # list keeps both, because that is the history (FR-504).
      assert length(open["data"]) == 2
      assert length(all["data"]) == 4
    end

    @tag req: ["FR-103"]
    test "a team you are not in has no list", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger |> get(~p"/api/v1/teams/#{ctx.team}/actions") |> json_response(404)
      assert stranger |> get(~p"/api/v1/teams/#{ctx.team}/actions/open") |> json_response(404)
    end
  end

  describe "PATCH /api/v1/actions/:id" do
    setup ctx do
      session = discussing(ctx)

      Map.merge(ctx, %{
        session: session,
        item: write(ctx.participant_conn, session, %{title: "Fix it"})
      })
    end

    @tag req: ["FR-503"]
    test "a member moves it along", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/actions/#{ctx.item["id"]}", %{status: "in_progress"})
        |> json_response(200)

      assert body["data"]["status"] == "in_progress"
    end

    @tag req: ["FR-503"]
    test "and can still do it after the session closed", ctx do
      {:ok, _closed} = Retro.close_session(ctx.facilitator, ctx.session)

      body =
        ctx.participant_conn
        |> patch(~p"/api/v1/actions/#{ctx.item["id"]}", %{status: "done"})
        |> json_response(200)

      assert body["data"]["status"] == "done"
    end

    @tag req: ["FR-502"]
    test "an unknown status is refused", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/actions/#{ctx.item["id"]}", %{status: "maybe"})
        |> json_response(422)

      assert body["error"]["details"]["fields"]["status"]
    end

    @tag req: ["FR-503"]
    test "an unknown item is not found", ctx do
      assert ctx.conn |> patch(~p"/api/v1/actions/0", %{status: "done"}) |> json_response(404)
    end

    @tag req: ["FR-103"]
    test "a stranger changes nothing", %{conn: conn} = ctx do
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger
             |> patch(~p"/api/v1/actions/#{ctx.item["id"]}", %{status: "done"})
             |> json_response(404)
    end
  end

  describe "POST /api/v1/sessions/:id/actions/:action_id/carry-over" do
    setup ctx do
      last = discussing(ctx)
      item = write(ctx.participant_conn, last, %{title: "Write the runbook"})
      {:ok, _closed} = Retro.close_session(ctx.facilitator, last)

      Map.merge(ctx, %{last: last, item: item, next: checking_in(ctx)})
    end

    @tag req: ["FR-505"]
    test "carries an open item into the new session, keeping the link", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.next}/actions/#{ctx.item["id"]}/carry-over")
        |> json_response(201)

      assert body["data"]["carried_from_id"] == ctx.item["id"]
      assert body["data"]["session_id"] == ctx.next.id
      assert body["data"]["title"] == "Write the runbook"
    end

    @tag req: ["FR-505"]
    test "an item that is finished is not carried", ctx do
      ctx.conn
      |> patch(~p"/api/v1/actions/#{ctx.item["id"]}", %{status: "done"})
      |> json_response(200)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.next}/actions/#{ctx.item["id"]}/carry-over")
        |> json_response(422)

      assert body["error"]["code"] == "wrong_state"
    end

    @tag req: ["FR-505"]
    test "carrying belongs to check-in", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.next, :brainstorm)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{brainstorming}/actions/#{ctx.item["id"]}/carry-over")
        |> json_response(422)

      assert body["error"]["code"] == "wrong_phase"
    end

    @tag req: ["FR-505"]
    test "an item is carried once", ctx do
      ctx.conn
      |> post(~p"/api/v1/sessions/#{ctx.next}/actions/#{ctx.item["id"]}/carry-over")
      |> json_response(201)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{ctx.next}/actions/#{ctx.item["id"]}/carry-over")
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
    end

    @tag req: ["FR-103"]
    test "an item from another team is not carried in", ctx do
      elsewhere = team_with_lead(ctx.facilitator)
      {:ok, theirs} = Retro.create_session(ctx.facilitator, elsewhere, %{title: "T"})
      {:ok, theirs} = Retro.start_session(ctx.facilitator, theirs)
      {:ok, theirs} = Retro.set_phase(ctx.facilitator, theirs, :discuss)
      {:ok, stray} = Actions.create_action(ctx.facilitator, theirs, %{title: "theirs"})

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{ctx.next}/actions/#{stray.id}/carry-over")
             |> json_response(404)
    end
  end
end
