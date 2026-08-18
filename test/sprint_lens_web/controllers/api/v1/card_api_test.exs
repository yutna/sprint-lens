defmodule SprintLensWeb.Api.V1.CardApiTest do
  @moduledoc """
  The `/api/v1` card surface (§7.2).

  The point of these tests is that the API is not a back door. Blind mode,
  anonymity, phase gating and authorship all have to hold here exactly as they
  hold on the board, because a client that can read JSON would otherwise see
  what the screen refuses to show (FR-209, FR-210, NFR-201).
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

  defp brainstorming(ctx, attrs \\ %{}) do
    {:ok, session} =
      Retro.create_session(ctx.facilitator, ctx.team, Map.merge(%{title: "R"}, attrs))

    {:ok, session} = Retro.start_session(ctx.facilitator, session)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    session
  end

  defp columns(session), do: Enum.sort_by(session.columns, & &1.position)

  defp write(conn, session, column, text) do
    conn
    |> post(~p"/api/v1/sessions/#{session}/cards", %{column_id: column.id, text: text})
    |> json_response(201)
    |> Map.fetch!("data")
  end

  describe "POST /api/v1/sessions/:id/cards" do
    @tag req: ["FR-301"]
    test "writes a card and names its author", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)

      card = write(ctx.conn, session, column, "We shipped early")

      assert card["text"] == "We shipped early"
      assert card["column_id"] == column.id
      assert card["author"]["id"] == ctx.facilitator.id
      assert card["created_at"]
    end

    @tag req: ["FR-301"]
    test "accepts fields nested under card", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/cards", %{
          card: %{column_id: column.id, text: "Nested"}
        })
        |> json_response(201)

      assert body["data"]["text"] == "Nested"
    end

    @tag req: ["FR-301"]
    test "rejects text over the limit", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/cards", %{
          column_id: column.id,
          text: String.duplicate("x", 501)
        })
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["fields"]["text"]
    end

    @tag req: ["FR-303"]
    test "refuses a column from another session", ctx do
      session = brainstorming(ctx)
      other = brainstorming(ctx)
      [column | _] = columns(other)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/cards", %{column_id: column.id, text: "Stray"})
        |> json_response(404)

      assert body["error"]["code"] == "not_found"
    end

    @tag req: ["FR-205"]
    test "refuses writing outside the brainstorm phase", ctx do
      session = brainstorming(ctx)
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :vote)
      [column | _] = columns(session)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/cards", %{column_id: column.id, text: "Late"})
        |> json_response(422)

      assert body["error"]["code"] == "wrong_phase"
    end

    @tag req: ["FR-103"]
    test "refuses a stranger", %{conn: conn} = ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger
             |> post(~p"/api/v1/sessions/#{session}/cards", %{column_id: column.id, text: "No"})
             |> json_response(404)
    end

    # Idempotency is §7.5, which carries no FR id of its own; the behaviour
    # belongs to creating a card.
    @tag req: ["FR-301"]
    test "returns the same card for a repeated request id (§7.5)", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)

      params = %{column_id: column.id, text: "Once", client_request_id: "abc-123"}

      first =
        ctx.conn |> post(~p"/api/v1/sessions/#{session}/cards", params) |> json_response(201)

      again =
        ctx.conn |> post(~p"/api/v1/sessions/#{session}/cards", params) |> json_response(201)

      assert first["data"]["id"] == again["data"]["id"]
      assert length(Board.list_cards(session)) == 1
    end
  end

  describe "GET /api/v1/sessions/:id/cards" do
    @tag req: ["FR-209"]
    test "shows only the caller's own cards while blind", ctx do
      session = brainstorming(ctx, %{is_blind: true})
      [column | _] = columns(session)

      write(ctx.conn, session, column, "Mine")
      write(ctx.participant_conn, session, column, "Theirs")

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}/cards") |> json_response(200)

      assert Enum.map(body["data"]["cards"], & &1["text"]) == ["Mine"]
    end

    @tag req: ["FR-209"]
    test "shows everything once revealed", ctx do
      session = brainstorming(ctx, %{is_blind: true})
      [column | _] = columns(session)

      write(ctx.conn, session, column, "Mine")
      write(ctx.participant_conn, session, column, "Theirs")

      assert ctx.conn
             |> post(~p"/api/v1/sessions/#{session}/reveal")
             |> json_response(200) == %{"data" => %{"cards_revealed" => true}}

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}/cards") |> json_response(200)

      assert Enum.sort(Enum.map(body["data"]["cards"], & &1["text"])) == ["Mine", "Theirs"]
    end

    @tag req: ["FR-304"]
    test "returns clusters alongside the cards", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.conn, session, column, "Slow builds")
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :group)

      ctx.conn
      |> post(~p"/api/v1/sessions/#{session}/groups", %{
        label: "Tooling",
        card_ids: [card["id"]]
      })
      |> json_response(201)

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}/cards") |> json_response(200)

      assert [%{"label" => "Tooling", "card_ids" => ids}] = body["data"]["groups"]
      assert ids == [card["id"]]
    end

    @tag req: ["FR-302"]
    test "only the facilitator may reveal", ctx do
      session = brainstorming(ctx, %{is_blind: true})

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/reveal")
        |> json_response(403)

      assert body["error"]["code"] == "forbidden"
    end

    @tag req: ["FR-210"]
    test "omits authorship entirely in an anonymous session", ctx do
      session = brainstorming(ctx, %{is_anonymous: true})
      [column | _] = columns(session)

      write(ctx.participant_conn, session, column, "Anon")

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}/cards") |> json_response(200)
      [card] = body["data"]["cards"]

      # Not `nil` — absent. A key that appears only sometimes is a signal in
      # itself, and the facilitator is not an exception here.
      refute Map.has_key?(card, "author")
      refute body |> Jason.encode!() |> String.contains?(ctx.participant.display_name)
    end

    @tag req: ["FR-210", "FR-605"]
    test "an Org Admin reading the API is told no more than anyone else", %{conn: conn} = ctx do
      session = brainstorming(ctx, %{is_anonymous: true})
      [column | _] = columns(session)
      write(ctx.participant_conn, session, column, "Anon")

      admin = insert(:org_admin, language: "en")
      join_team(admin, ctx.team)

      body =
        conn
        |> authed(admin)
        |> get(~p"/api/v1/sessions/#{session}/cards")
        |> json_response(200)

      [card] = body["data"]["cards"]

      refute Map.has_key?(card, "author")
      refute body |> Jason.encode!() |> String.contains?(ctx.participant.display_name)
    end

    @tag req: ["FR-210", "NFR-304"]
    test "a closed anonymous session has no author left to hide", ctx do
      session = brainstorming(ctx, %{is_anonymous: true})
      [column | _] = columns(session)
      write(ctx.participant_conn, session, column, "Signed while it ran")

      {:ok, session} = Retro.close_session(ctx.facilitator, session)

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}/cards") |> json_response(200)
      [card] = body["data"]["cards"]

      assert card["text"] == "Signed while it ran"
      refute Map.has_key?(card, "author")
      # Not merely omitted by the serialiser — gone from the row (§6.4).
      assert [%{author_id: nil}] = Board.list_cards(session)
    end

    @tag req: ["FR-301"]
    test "keeps authorship when the session was never anonymous", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      write(ctx.participant_conn, session, column, "Signed")

      {:ok, session} = Retro.close_session(ctx.facilitator, session)

      body = ctx.conn |> get(~p"/api/v1/sessions/#{session}/cards") |> json_response(200)
      [card] = body["data"]["cards"]

      assert card["author"]["id"] == ctx.participant.id
    end
  end

  describe "PATCH /api/v1/cards/:id" do
    @tag req: ["FR-301"]
    test "edits the caller's own card", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.conn, session, column, "Draft")

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{text: "Final"})
        |> json_response(200)

      assert body["data"]["text"] == "Final"
    end

    @tag req: ["FR-301", "FR-302"]
    test "refuses to let the facilitator rewrite someone else's card", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.participant_conn, session, column, "Their words")

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{text: "My words"})
        |> json_response(403)

      assert body["error"]["code"] == "forbidden"
    end

    @tag req: ["FR-303", "FR-305"]
    test "moves a card to another column at a position", ctx do
      session = brainstorming(ctx)
      [first, second | _] = columns(session)

      write(ctx.conn, session, second, "Already there")
      card = write(ctx.conn, session, first, "Moving")

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{column_id: second.id, position: 0})
        |> json_response(200)

      assert body["data"]["column_id"] == second.id
      assert body["data"]["position"] == 0
    end

    @tag req: ["FR-305"]
    test "reads a position sent as a string", ctx do
      session = brainstorming(ctx)
      [first, second | _] = columns(session)

      write(ctx.conn, session, second, "Already there")
      card = write(ctx.conn, session, first, "Moving")

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{column_id: second.id, position: "0"})
        |> json_response(200)

      assert body["data"]["position"] == 0
    end

    @tag req: ["FR-305"]
    test "moves to the top when no position is given", ctx do
      session = brainstorming(ctx)
      [first, second | _] = columns(session)

      write(ctx.conn, session, second, "Already there")
      card = write(ctx.conn, session, first, "Moving")

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{column_id: second.id})
        |> json_response(200)

      assert body["data"]["column_id"] == second.id
      assert body["data"]["position"] == 0
    end

    @tag req: ["FR-305"]
    test "puts a card with an unreadable position at the top", ctx do
      session = brainstorming(ctx)
      [first, second | _] = columns(session)

      write(ctx.conn, session, second, "Already there")
      card = write(ctx.conn, session, first, "Moving")

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{column_id: second.id, position: "top"})
        |> json_response(200)

      assert body["data"]["position"] == 0
    end

    @tag req: ["FR-304"]
    test "puts a card into a cluster and takes it back out", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.conn, session, column, "Grouped")
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :group)

      group =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/groups", %{label: "Process"})
        |> json_response(201)
        |> Map.fetch!("data")

      joined =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{card_group_id: group["id"]})
        |> json_response(200)

      assert joined["data"]["card_group_id"] == group["id"]

      left =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{card_group_id: nil})
        |> json_response(200)

      assert left["data"]["card_group_id"] == nil
    end

    @tag req: ["FR-304"]
    test "refuses a cluster from another session", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.conn, session, column, "Grouped")
      {:ok, _session} = Retro.set_phase(ctx.facilitator, session, :group)

      other = brainstorming(ctx)
      {:ok, other} = Retro.set_phase(ctx.facilitator, other, :group)
      {:ok, stray} = Board.create_group(ctx.facilitator, other, "Elsewhere", [])

      body =
        ctx.conn
        |> patch(~p"/api/v1/cards/#{card["id"]}", %{card_group_id: stray.id})
        |> json_response(404)

      assert body["error"]["code"] == "not_found"
    end

    @tag req: ["FR-301"]
    test "reports an unknown card as not found", ctx do
      body = ctx.conn |> patch(~p"/api/v1/cards/0", %{text: "Ghost"}) |> json_response(404)

      assert body["error"]["code"] == "not_found"
    end

    @tag req: ["FR-103"]
    test "refuses a card in a team the caller is not in", %{conn: conn} = ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.conn, session, column, "Private")
      stranger = authed(conn, insert(:user, language: "en"))

      assert stranger
             |> patch(~p"/api/v1/cards/#{card["id"]}", %{text: "Peeking"})
             |> json_response(404)
    end
  end

  describe "DELETE /api/v1/cards/:id" do
    @tag req: ["FR-301"]
    test "deletes the caller's own card", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.participant_conn, session, column, "Mine to remove")

      assert ctx.participant_conn
             |> delete(~p"/api/v1/cards/#{card["id"]}")
             |> response(204) == ""

      assert Board.list_cards(session) == []
    end

    @tag req: ["FR-302"]
    test "lets the facilitator delete any card", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.participant_conn, session, column, "Off topic")

      assert ctx.conn |> delete(~p"/api/v1/cards/#{card["id"]}") |> response(204)
      assert Board.list_cards(session) == []
    end

    @tag req: ["FR-301"]
    test "refuses a participant deleting someone else's card", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      card = write(ctx.conn, session, column, "Not yours")

      body =
        ctx.participant_conn
        |> delete(~p"/api/v1/cards/#{card["id"]}")
        |> json_response(403)

      assert body["error"]["code"] == "forbidden"
    end

    @tag req: ["FR-301"]
    test "reports an unknown card as not found", ctx do
      assert ctx.conn |> delete(~p"/api/v1/cards/0") |> json_response(404)
    end
  end

  describe "POST /api/v1/sessions/:id/groups" do
    @tag req: ["FR-304"]
    test "creates a cluster holding the given cards", ctx do
      session = brainstorming(ctx)
      [column | _] = columns(session)
      one = write(ctx.conn, session, column, "Slow builds")
      two = write(ctx.conn, session, column, "Flaky CI")
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :group)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/groups", %{
          label: "Tooling",
          card_ids: [one["id"], two["id"]]
        })
        |> json_response(201)

      assert body["data"]["label"] == "Tooling"
      assert Enum.sort(body["data"]["card_ids"]) == Enum.sort([one["id"], two["id"]])
    end

    @tag req: ["FR-209"]
    test "names only the cards the caller may see", ctx do
      session = brainstorming(ctx, %{is_blind: true})
      [column | _] = columns(session)
      mine = write(ctx.conn, session, column, "Mine")
      theirs = write(ctx.participant_conn, session, column, "Theirs")
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :group)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/groups", %{
          label: "Everything",
          card_ids: [mine["id"], theirs["id"]]
        })
        |> json_response(201)

      assert body["data"]["card_ids"] == [mine["id"]]
    end

    @tag req: ["FR-205"]
    test "refuses grouping outside the group phase", ctx do
      session = brainstorming(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/groups", %{label: "Too early"})
        |> json_response(422)

      assert body["error"]["code"] == "wrong_phase"
    end

    @tag req: ["FR-304"]
    test "rejects a cluster with no label", ctx do
      session = brainstorming(ctx)
      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :group)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/groups", %{label: ""})
        |> json_response(422)

      assert body["error"]["details"]["fields"]["label"]
    end
  end

  describe "POST /api/v1/sessions/:id/mood" do
    @tag req: ["FR-211"]
    test "records a check-in mood and returns only the aggregate", ctx do
      {:ok, session} =
        Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})

      {:ok, session} = Retro.start_session(ctx.facilitator, session)

      ctx.conn
      |> post(~p"/api/v1/sessions/#{session}/mood", %{
        kind: "checkin_mood",
        score: 4,
        word: "steady"
      })
      |> json_response(200)

      body =
        ctx.participant_conn
        |> post(~p"/api/v1/sessions/#{session}/mood", %{kind: "checkin_mood", score: 2})
        |> json_response(200)

      assert body["data"]["count"] == 2
      assert body["data"]["average"] == 3.0
      assert body["data"]["words"] == ["steady"]
      refute body |> Jason.encode!() |> String.contains?(ctx.facilitator.display_name)
    end

    @tag req: ["FR-211"]
    test "rejects an unknown kind", ctx do
      session = brainstorming(ctx)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/mood", %{kind: "vibes", score: 3})
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
    end

    @tag req: ["FR-211"]
    test "rejects a score outside 1..5", ctx do
      {:ok, session} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "R"})
      {:ok, session} = Retro.start_session(ctx.facilitator, session)

      body =
        ctx.conn
        |> post(~p"/api/v1/sessions/#{session}/mood", %{kind: "checkin_mood", score: 9})
        |> json_response(422)

      assert body["error"]["details"]["fields"]["score"]
    end
  end
end
