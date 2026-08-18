defmodule SprintLensWeb.Api.V1.TeamApiTest do
  @moduledoc """
  The `/api/v1/teams` surface (§7.2).

  These assert the same rules the LiveView tests assert, on purpose: both are
  thin adapters over `SprintLens.Teams`, and a permission that holds on one
  surface but not the other is the failure NFR-201 exists to prevent.
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Teams

  setup %{conn: conn} do
    # The API answers in the caller's language (FR-906); these assert English
    # copy, so the caller speaks English.
    user = insert(:user, language: "en")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> Accounts.create_api_token(user))

    %{conn: conn, user: user}
  end

  describe "GET /api/v1/teams" do
    @tag req: ["FR-103"]
    test "lists only the caller's teams", %{conn: conn, user: user} do
      mine = team_with_lead(user)
      _theirs = team_with_lead(insert(:user))

      body = conn |> get(~p"/api/v1/teams") |> json_response(200)

      assert [%{"id" => id, "name" => name}] = body["data"]
      assert id == mine.id
      assert name == mine.name
    end

    @tag req: ["NFR-201"]
    test "refuses an unauthenticated caller" do
      assert build_conn()
             |> put_req_header("accept", "application/json")
             |> get(~p"/api/v1/teams")
             |> json_response(401)
    end
  end

  describe "POST /api/v1/teams" do
    @tag req: ["FR-101"]
    test "creates a team with the caller as lead", %{conn: conn, user: user} do
      body = conn |> post(~p"/api/v1/teams", %{name: "Alpha"}) |> json_response(201)

      assert body["data"]["name"] == "Alpha"
      assert [%{"role" => "lead"}] = body["data"]["members"]
      assert Teams.role(user, body["data"]["id"]) == :lead
    end

    @tag req: ["FR-101"]
    test "accepts the fields nested under team", %{conn: conn} do
      assert conn
             |> post(~p"/api/v1/teams", %{team: %{name: "Nested"}})
             |> json_response(201)
    end

    @tag req: ["FR-919"]
    test "reports a missing name in the shared error envelope", %{conn: conn} do
      body = conn |> post(~p"/api/v1/teams", %{name: ""}) |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["fields"]["name"] == ["can't be blank"]
    end
  end

  describe "GET /api/v1/teams/:id" do
    @tag req: ["FR-102"]
    test "returns the team with its members", %{conn: conn, user: user} do
      team = team_with_lead(user)
      teammate = insert(:user)
      join_team(teammate, team)

      body = conn |> get(~p"/api/v1/teams/#{team}") |> json_response(200)

      assert body["data"]["id"] == team.id
      assert length(body["data"]["members"]) == 2
    end

    # Data minimisation. NFR-301 (PDPA conformance as a whole) stays a
    # documented gap; this covers one concrete mechanism behind it.
    test "a member payload carries a name, never an email", %{conn: conn, user: user} do
      team = team_with_lead(user)

      body = conn |> get(~p"/api/v1/teams/#{team}") |> json_response(200)

      assert [%{"user" => member}] = body["data"]["members"]
      assert member["display_name"] == user.display_name
      refute Map.has_key?(member, "email")
    end

    @tag req: ["FR-919"]
    test "an id that is not a number is not found rather than a crash", %{conn: conn} do
      body = conn |> get(~p"/api/v1/teams/not-a-number") |> json_response(404)

      assert body["error"]["code"] == "not_found"
    end

    @tag req: ["FR-103"]
    test "hides a team the caller does not belong to", %{conn: conn} do
      theirs = team_with_lead(insert(:user))

      assert conn |> get(~p"/api/v1/teams/#{theirs}") |> json_response(404)
    end
  end

  describe "PATCH /api/v1/teams/:id" do
    @tag req: ["FR-105", "AI-003"]
    test "a lead updates the settings", %{conn: conn, user: user} do
      team = team_with_lead(user)

      body =
        conn
        |> patch(~p"/api/v1/teams/#{team}", %{default_vote_budget: 7, ai_opt_in: true})
        |> json_response(200)

      assert body["data"]["default_vote_budget"] == 7
      assert body["data"]["ai_opt_in"]
    end

    @tag req: ["NFR-201"]
    test "a plain member cannot", %{conn: conn, user: user} do
      team = team_with_lead(insert(:user))
      join_team(user, team)

      assert conn
             |> patch(~p"/api/v1/teams/#{team}", %{ai_opt_in: true})
             |> json_response(403)
    end

    @tag req: ["FR-106"]
    test "an archived team refuses changes", %{conn: conn, user: user} do
      team = team_with_lead(user, %{is_archived: true})

      assert conn |> patch(~p"/api/v1/teams/#{team}", %{ai_opt_in: true}) |> json_response(403)
    end
  end

  describe "archive and restore" do
    @tag req: ["FR-106"]
    test "a lead archives and restores", %{conn: conn, user: user} do
      team = team_with_lead(user)

      assert conn |> post(~p"/api/v1/teams/#{team}/archive") |> json_response(200)
      assert conn |> post(~p"/api/v1/teams/#{team}/restore") |> json_response(200)

      {:ok, restored} = Teams.fetch_team(user, team.id)
      refute restored.is_archived
    end

    @tag req: ["NFR-201"]
    test "a member cannot", %{conn: conn, user: user} do
      team = team_with_lead(insert(:user))
      join_team(user, team)

      assert conn |> post(~p"/api/v1/teams/#{team}/archive") |> json_response(403)
    end
  end

  describe "membership endpoints" do
    setup %{user: user} do
      %{team: team_with_lead(user), newcomer: insert(:user)}
    end

    @tag req: ["FR-102"]
    test "adds a member by id", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/teams/#{ctx.team}/members", %{user_id: ctx.newcomer.id})
        |> json_response(201)

      assert length(body["data"]) == 2
      assert Teams.role(ctx.newcomer, ctx.team) == :member
    end

    @tag req: ["FR-102"]
    test "adds a member by email, in a chosen role", ctx do
      ctx.conn
      |> post(~p"/api/v1/teams/#{ctx.team}/members", %{email: ctx.newcomer.email, role: "lead"})
      |> json_response(201)

      assert Teams.role(ctx.newcomer, ctx.team) == :lead
    end

    @tag req: ["FR-919"]
    test "refuses a request that identifies nobody", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/teams/#{ctx.team}/members", %{})
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
    end

    @tag req: ["FR-102"]
    test "removes a member", ctx do
      join_team(ctx.newcomer, ctx.team)

      assert ctx.conn
             |> delete(~p"/api/v1/teams/#{ctx.team}/members/#{ctx.newcomer.id}")
             |> response(204)

      assert Teams.role(ctx.newcomer, ctx.team) == nil
    end

    @tag req: ["FR-102"]
    test "refuses to remove the last lead", ctx do
      body =
        ctx.conn
        |> delete(~p"/api/v1/teams/#{ctx.team}/members/#{ctx.user.id}")
        |> json_response(422)

      assert body["error"]["code"] == "last_lead"
    end

    @tag req: ["FR-104"]
    test "a member leaves of their own accord", %{conn: conn, user: user} do
      team = team_with_lead(insert(:user))
      join_team(user, team)

      assert conn |> delete(~p"/api/v1/teams/#{team}/members") |> response(204)
      assert Teams.role(user, team) == nil
    end

    @tag req: ["NFR-201"]
    test "a member cannot add or remove anyone", %{conn: conn, user: user} do
      team = team_with_lead(insert(:user))
      join_team(user, team)

      assert conn
             |> post(~p"/api/v1/teams/#{team}/members", %{user_id: insert(:user).id})
             |> json_response(403)
    end
  end

  describe "template endpoints" do
    setup %{user: user} do
      %{team: team_with_lead(user)}
    end

    @tag req: ["FR-201"]
    test "lists the built-ins and the team's own", ctx do
      body = ctx.conn |> get(~p"/api/v1/teams/#{ctx.team}/templates") |> json_response(200)

      names = Enum.map(body["data"], & &1["name"])
      assert "Start-Stop-Continue" in names
      assert Enum.all?(body["data"], &is_list(&1["columns"]))
    end

    @tag req: ["FR-202"]
    test "creates a custom template", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/teams/#{ctx.team}/templates", %{
          name: "Ours",
          columns: [%{"name" => "Good", "hint" => "?"}, %{"name" => "Bad"}]
        })
        |> json_response(201)

      assert body["data"]["name"] == "Ours"

      assert [%{"name" => "Good", "hint" => "?"}, %{"name" => "Bad", "hint" => nil}] =
               body["data"]["columns"]
    end

    @tag req: ["FR-202"]
    test "refuses a layout outside the column bounds", ctx do
      body =
        ctx.conn
        |> post(~p"/api/v1/teams/#{ctx.team}/templates", %{
          name: "Too few",
          columns: [%{"name" => "Only"}]
        })
        |> json_response(422)

      assert body["error"]["details"]["fields"]["columns"] != []
    end

    @tag req: ["FR-202"]
    test "deletes the team's own template", ctx do
      {:ok, template} =
        Teams.create_template(ctx.user, ctx.team, %{
          name: "Doomed",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      assert ctx.conn
             |> delete(~p"/api/v1/teams/#{ctx.team}/templates/#{template.id}")
             |> response(204)
    end

    @tag req: ["FR-201"]
    test "refuses to delete a built-in", ctx do
      builtin = hd(Teams.list_builtin_templates())

      body =
        ctx.conn
        |> delete(~p"/api/v1/teams/#{ctx.team}/templates/#{builtin.id}")
        |> json_response(422)

      assert body["error"]["code"] == "builtin"
    end

    @tag req: ["FR-103"]
    test "cannot reach another team's template", ctx do
      other_lead = insert(:user)
      other_team = team_with_lead(other_lead)

      {:ok, theirs} =
        Teams.create_template(other_lead, other_team, %{
          name: "Theirs",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      assert ctx.conn
             |> delete(~p"/api/v1/teams/#{ctx.team}/templates/#{theirs.id}")
             |> json_response(404)
    end
  end
end
