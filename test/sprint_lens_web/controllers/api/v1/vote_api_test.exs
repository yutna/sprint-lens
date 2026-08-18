defmodule SprintLensWeb.Api.V1.VoteApiTest do
  @moduledoc """
  The `/api/v1` voting and discussion surface (§7.2).

  The rule these tests exist for is that the API hides what the screen hides.
  A total the board withholds until the reveal (FR-404) must not be readable
  as JSON in the meantime, and one person's budget is not another's to fetch
  (FR-403).
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Retro
  alias SprintLens.Retro.Board

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

  defp voting(ctx, attrs \\ %{}) do
    {:ok, session} =
      Retro.create_session(ctx.facilitator, ctx.team, Map.merge(%{title: "R"}, attrs))

    {:ok, session} = Retro.start_session(ctx.facilitator, session)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    column = hd(session.columns)

    cards =
      for text <- ["Slow builds", "Flaky CI", "Good pairing"] do
        {:ok, card} =
          Board.create_card(ctx.participant, session, %{column_id: column.id, text: text})

        card
      end

    {:ok, grouping} = Retro.set_phase(ctx.facilitator, session, :group)

    {:ok, group} =
      Board.create_group(
        ctx.participant,
        grouping,
        "Tooling",
        cards |> Enum.take(2) |> Enum.map(& &1.id)
      )

    {:ok, session} = Retro.set_phase(ctx.facilitator, grouping, :vote)

    %{session: session, group: group, loose: List.last(cards)}
  end

  defp topics(conn, session) do
    conn
    |> get(~p"/api/v1/sessions/#{session}/topics")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  describe "POST /api/v1/sessions/:id/votes" do
    @tag req: ["FR-403"]
    test "casts a vote and answers with the caller's own budget", ctx do
      %{session: session, group: group} = voting(ctx)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{card_group_id: group.id})
        |> json_response(201)

      assert body["data"] == %{
               "budget" => 5,
               "used" => 1,
               "remaining" => 4,
               "revealed" => false
             }
    end

    @tag req: ["FR-403"]
    test "a topic key names the same thing the two ids do", ctx do
      %{session: session, loose: loose} = voting(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/votes", %{topic: "card:#{loose.id}"})
             |> json_response(201)
    end

    @tag req: ["FR-403"]
    test "retracting goes through the same endpoint", ctx do
      %{session: session, loose: loose} = voting(ctx)

      ctx.participant_conn
      |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
      |> json_response(201)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id, retract: true})
        |> json_response(200)

      assert body["data"]["used"] == 0
    end

    @tag req: ["FR-403"]
    test "retracting a vote never cast is not found", ctx do
      %{session: session, loose: loose} = voting(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id, retract: true})
             |> json_response(404)
    end

    @tag req: ["FR-401"]
    test "spending past the budget says what the budget was", ctx do
      %{session: session, loose: loose} = voting(ctx, %{vote_budget: 1, multi_vote: true})

      ctx.participant_conn
      |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
      |> json_response(201)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
        |> json_response(422)

      assert body["error"]["code"] == "vote_budget_exceeded"
      assert body["error"]["details"] == %{"budget" => 1, "used" => 1}
    end

    @tag req: ["FR-402"]
    test "a second vote on the same topic is refused by default", ctx do
      %{session: session, loose: loose} = voting(ctx)

      ctx.participant_conn
      |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
      |> json_response(201)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
        |> json_response(422)

      assert body["error"]["code"] == "already_voted"
    end

    @tag req: ["FR-301"]
    test "a repeated request id casts one vote (§7.5)", ctx do
      %{session: session, loose: loose} = voting(ctx)
      params = %{card_id: loose.id, client_request_id: "v-1"}

      ctx.participant_conn
      |> post(~p"/api/v1/sessions/#{session}/votes", params)
      |> json_response(201)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", params)
        |> json_response(201)

      assert body["data"]["used"] == 1
    end

    @tag req: ["FR-403"]
    test "a vote for nothing, or for two things, is refused", ctx do
      %{session: session, loose: loose, group: group} = voting(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/votes", %{})
             |> json_response(404)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{
          card_id: loose.id,
          card_group_id: group.id
        })
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
    end

    @tag req: ["FR-403"]
    test "voting outside the vote phase is refused", ctx do
      %{session: session, loose: loose} = voting(ctx)
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :discuss)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
        |> json_response(422)

      assert body["error"]["code"] == "wrong_phase"
    end
  end

  describe "GET /api/v1/sessions/:id/topics" do
    @tag req: ["FR-404"]
    test "withholds the totals until the facilitator reveals them", ctx do
      %{session: session, group: group} = voting(ctx)

      ctx.participant_conn
      |> post(~p"/api/v1/sessions/#{session}/votes", %{card_group_id: group.id})
      |> json_response(201)

      # Hidden from the facilitator too — the API is not a way around FR-404.
      for conn <- [ctx.conn, ctx.participant_conn] do
        data = topics(conn, session)

        assert Enum.all?(data["topics"], &is_nil(&1["votes"]))
        refute data["votes"]["revealed"]
      end
    end

    @tag req: ["FR-403"]
    test "each caller sees their own count and nobody else's", ctx do
      %{session: session, group: group} = voting(ctx)

      ctx.participant_conn
      |> post(~p"/api/v1/sessions/#{session}/votes", %{card_group_id: group.id})
      |> json_response(201)

      mine = topics(ctx.participant_conn, session)
      theirs = topics(ctx.conn, session)

      assert Enum.find(mine["topics"], &(&1["kind"] == "group"))["my_votes"] == 1
      assert Enum.find(theirs["topics"], &(&1["kind"] == "group"))["my_votes"] == 0
      assert theirs["votes"]["used"] == 0
    end

    @tag req: ["FR-404", "FR-405"]
    test "after the reveal the totals are out and the order follows them", ctx do
      %{session: session, group: group, loose: loose} = voting(ctx, %{multi_vote: true})

      for _ <- 1..2 do
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
        |> json_response(201)
      end

      ctx.conn
      |> post(~p"/api/v1/sessions/#{session}/votes", %{card_group_id: group.id})
      |> json_response(201)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/votes/reveal")
             |> json_response(200) == %{"data" => %{"votes_revealed" => true}}

      data = topics(ctx.participant_conn, session)

      assert [top | _rest] = data["topics"]
      assert top["key"] == "card:#{loose.id}"
      assert top["votes"] == 2
    end

    @tag req: ["FR-405"]
    test "a cluster names the cards it holds, and they are not topics too", ctx do
      %{session: session, group: group, loose: loose} = voting(ctx)

      data = topics(ctx.conn, session)

      assert length(data["topics"]) == 2

      cluster = Enum.find(data["topics"], &(&1["kind"] == "group"))
      assert cluster["key"] == "group:#{group.id}"
      assert length(cluster["card_ids"]) == 2

      assert Enum.any?(data["topics"], &(&1["key"] == "card:#{loose.id}"))
    end

    @tag req: ["FR-404"]
    test "only the facilitator reveals", ctx do
      %{session: session} = voting(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/votes/reveal")
             |> json_response(403)
    end
  end

  describe "POST /api/v1/sessions/:id/focus" do
    @tag req: ["FR-406"]
    test "the facilitator points the room at a topic", ctx do
      %{session: session, group: group} = voting(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/focus", %{card_group_id: group.id})
        |> json_response(200)

      assert body["data"]["topic"] == "group:#{group.id}"
      assert Enum.find(topics(ctx.participant_conn, session)["topics"], & &1["focused"])
    end

    @tag req: ["FR-406"]
    test "a topic key works here too", ctx do
      %{session: session, loose: loose} = voting(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/focus", %{topic: "card:#{loose.id}"})
        |> json_response(200)

      assert body["data"]["topic"] == "card:#{loose.id}"
    end

    @tag req: ["FR-406"]
    test "sending no topic empties the spotlight", ctx do
      %{session: session, loose: loose} = voting(ctx)

      ctx.conn
      |> post(~p"/api/v1/sessions/#{session}/focus", %{card_id: loose.id})
      |> json_response(200)

      body = ctx.conn |> post(~p"/api/v1/sessions/#{session}/focus", %{}) |> json_response(200)

      assert body["data"]["topic"] == nil
    end

    @tag req: ["FR-408"]
    test "focusing can start the discussion clock", ctx do
      %{session: session, loose: loose} = voting(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/focus", %{card_id: loose.id, timer_s: 300})
        |> json_response(200)

      assert body["data"]["timer_s"] == 300
    end

    @tag req: ["FR-406"]
    test "a participant does not decide what the room looks at", ctx do
      %{session: session, loose: loose} = voting(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/focus", %{card_id: loose.id})
             |> json_response(403)
    end

    @tag req: ["FR-406"]
    test "a topic from another session cannot be focused", ctx do
      %{session: session} = voting(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/focus", %{card_id: 0})
             |> json_response(404)
    end
  end

  describe "POST /api/v1/sessions/:id/notes" do
    @tag req: ["FR-407"]
    test "the facilitator records what the room decided", ctx do
      %{session: session, group: group} = voting(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/notes", %{
          card_group_id: group.id,
          body: "Fix the build first"
        })
        |> json_response(200)

      assert body["data"]["topic"] == "group:#{group.id}"
      assert body["data"]["body"] == "Fix the build first"

      cluster =
        Enum.find(topics(ctx.participant_conn, session)["topics"], &(&1["kind"] == "group"))

      assert cluster["note"] == "Fix the build first"
    end

    @tag req: ["FR-407"]
    test "an empty note is refused", ctx do
      %{session: session, loose: loose} = voting(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/notes", %{card_id: loose.id, body: "  "})
        |> json_response(422)

      assert body["error"]["details"]["fields"]["body"]
    end

    @tag req: ["FR-407"]
    test "a participant does not write the record", ctx do
      %{session: session, loose: loose} = voting(ctx)

      assert ctx.participant_conn
             |> post(~p"/api/v1/sessions/#{session}/notes", %{card_id: loose.id, body: "mine"})
             |> json_response(403)
    end

    @tag req: ["FR-407"]
    test "a note needs a topic to be about", ctx do
      %{session: session} = voting(ctx)

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/notes", %{body: "floating"})
             |> json_response(404)
    end
  end

  @tag req: ["FR-103"]
  test "a stranger reaches none of it", %{conn: conn} = ctx do
    %{session: session, loose: loose} = voting(ctx)
    stranger = authed(conn, insert(:user, language: "en"))

    assert stranger |> get(~p"/api/v1/sessions/#{session}/topics") |> json_response(404)

    assert stranger
           |> post(~p"/api/v1/sessions/#{session}/votes", %{card_id: loose.id})
           |> json_response(404)

    assert stranger |> post(~p"/api/v1/sessions/#{session}/focus", %{}) |> json_response(404)
  end
end
