defmodule SprintLensWeb.Api.V1.AdminApiTest do
  @moduledoc """
  The `/api/v1/admin` surface (§7.2).

  Every endpoint here refuses with 403 rather than 404: unlike another team's
  board (FR-103), an administration endpoint is not a secret. The answer to
  "may I?" is no, not "there is nothing here".
  """

  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts
  alias SprintLens.Accounts.User
  alias SprintLens.Admin
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Session
  alias SprintLens.Teams.Team

  setup %{conn: conn} do
    admin = insert(:org_admin, language: "en", display_name: "Admin")
    lead = insert(:user, language: "en", display_name: "Lek")
    team = team_with_lead(lead)
    member = insert(:user, language: "en", display_name: "Ploy")
    join_team(member, team)

    %{
      conn: authed(conn, admin),
      lead_conn: authed(conn, lead),
      admin: admin,
      lead: lead,
      member: member,
      team: team
    }
  end

  defp authed(conn, user) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> Accounts.create_api_token(user))
  end

  defp closed_session(ctx) do
    session = active_session(ctx.team, ctx.lead)
    {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)

    {:ok, card} =
      Board.create_card(ctx.member, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, closed} = Retro.close_session(ctx.lead, session)

    %{session: closed, card: card}
  end

  describe "GET /api/v1/admin/users" do
    @tag req: ["FR-801"]
    test "lists everybody, with what an administrator needs to tell them apart", ctx do
      body = ctx.conn |> get(~p"/api/v1/admin/users") |> json_response(200)

      person = Enum.find(body["data"], &(&1["id"] == ctx.member.id))

      assert person["display_name"] == "Ploy"
      assert person["email"] == ctx.member.email
      assert person["is_active"]
      refute person["is_erased"]
    end

    @tag req: ["FR-801"]
    test "and refuses anybody else outright", ctx do
      body = ctx.lead_conn |> get(~p"/api/v1/admin/users") |> json_response(403)

      assert body["error"]["code"] == "forbidden"
    end
  end

  describe "PATCH /api/v1/admin/users/:id" do
    @tag req: ["FR-005", "FR-801"]
    test "deactivates and reactivates", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/users/#{ctx.member}", %{action: "deactivate"})
        |> json_response(200)

      refute body["data"]["is_active"]

      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/users/#{ctx.member}", %{action: "reactivate"})
        |> json_response(200)

      assert body["data"]["is_active"]
    end

    @tag req: ["FR-805"]
    test "erases, leaving the content and taking the person", ctx do
      %{card: card} = closed_session(ctx)

      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/users/#{ctx.member}", %{action: "erase"})
        |> json_response(200)

      assert body["data"]["is_erased"]
      refute body |> Jason.encode!() |> String.contains?("Ploy")

      assert Repo.get(SprintLens.Retro.Card, card.id).author_id == nil
    end

    @tag req: ["FR-801"]
    test "refuses to strand a team without a lead", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/users/#{ctx.lead}", %{action: "deactivate"})
        |> json_response(422)

      assert body["error"]["code"] == "last_lead"
      assert body["error"]["details"]["team_ids"] == [ctx.team.id]
    end

    @tag req: ["FR-801"]
    test "an action nobody offers is refused, with the ones that exist", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/users/#{ctx.member}", %{action: "promote"})
        |> json_response(422)

      assert body["error"]["details"]["action"] == ["deactivate", "reactivate", "erase"]
    end

    @tag req: ["FR-801"]
    test "an unknown person is not found", ctx do
      assert ctx.conn
             |> patch(~p"/api/v1/admin/users/0", %{action: "deactivate"})
             |> json_response(404)
    end

    @tag req: ["FR-801"]
    test "and nobody but an Org Admin may ask", ctx do
      assert ctx.lead_conn
             |> patch(~p"/api/v1/admin/users/#{ctx.member}", %{action: "deactivate"})
             |> json_response(403)

      assert %User{is_active: true} = Repo.get(User, ctx.member.id)
    end
  end

  describe "the settings endpoints (FR-802, FR-806)" do
    @tag req: ["FR-802"]
    test "reads them, Thai by default", ctx do
      body = ctx.conn |> get(~p"/api/v1/admin/settings") |> json_response(200)

      assert body["data"]["default_language"] == "th"
      assert body["data"]["retention_days"] == 365
      assert body["data"]["ai_enabled"]
      assert body["data"]["webhooks_enabled"]
    end

    @tag req: ["FR-806"]
    test "and flips a kill switch", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/settings", %{ai_enabled: false})
        |> json_response(200)

      refute body["data"]["ai_enabled"]
      refute Admin.ai_enabled?()
    end

    @tag req: ["FR-802"]
    test "accepts fields nested under settings", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/settings", %{settings: %{retention_days: 90}})
        |> json_response(200)

      assert body["data"]["retention_days"] == 90
    end

    @tag req: ["FR-802"]
    test "a setting that makes no sense is refused", ctx do
      body =
        ctx.conn
        |> patch(~p"/api/v1/admin/settings", %{retention_days: 1})
        |> json_response(422)

      assert body["error"]["details"]["fields"]["retention_days"]
    end

    @tag req: ["FR-802"]
    test "and nobody else reads or writes them", ctx do
      assert ctx.lead_conn |> get(~p"/api/v1/admin/settings") |> json_response(403)

      assert ctx.lead_conn
             |> patch(~p"/api/v1/admin/settings", %{ai_enabled: false})
             |> json_response(403)
    end
  end

  describe "GET /api/v1/admin/audit" do
    @tag req: ["FR-807"]
    test "reads the log, newest first", ctx do
      ctx.conn
      |> patch(~p"/api/v1/admin/users/#{ctx.member}", %{action: "deactivate"})
      |> json_response(200)

      body = ctx.conn |> get(~p"/api/v1/admin/audit") |> json_response(200)

      assert [event] = body["data"]
      assert event["action"] == "user.deactivated"
      assert event["target"] == "user:#{ctx.member.id}"
      assert event["actor_id"] == ctx.admin.id
      assert event["occurred_at"]
    end

    @tag req: ["FR-807"]
    test "takes a limit, and ignores a silly one", ctx do
      for n <- 1..3, do: Admin.record_event(ctx.admin, "user.deactivated", "user:#{n}")

      assert ctx.conn
             |> get(~p"/api/v1/admin/audit?limit=2")
             |> json_response(200)
             |> Map.fetch!("data")
             |> length() == 2

      assert ctx.conn
             |> get(~p"/api/v1/admin/audit?limit=nonsense")
             |> json_response(200)
             |> Map.fetch!("data")
             |> length() == 3
    end

    @tag req: ["FR-807"]
    test "and nobody else reads it", ctx do
      assert ctx.lead_conn |> get(~p"/api/v1/admin/audit") |> json_response(403)
    end
  end

  describe "purging over the API (FR-804)" do
    setup ctx, do: Map.merge(ctx, closed_session(ctx))

    @tag req: ["FR-804"]
    test "a finished retrospective", ctx do
      assert ctx.conn
             |> delete(~p"/api/v1/admin/sessions/#{ctx.session}")
             |> response(204) == ""

      assert Repo.get(Session, ctx.session.id) == nil
    end

    @tag req: ["FR-804"]
    test "a whole team", ctx do
      assert ctx.conn |> delete(~p"/api/v1/admin/teams/#{ctx.team}") |> response(204)
      assert Repo.get(Team, ctx.team.id) == nil
    end

    @tag req: ["FR-804"]
    test "but not one that is still running", ctx do
      running = active_session(ctx.team, ctx.lead)

      body =
        ctx.conn |> delete(~p"/api/v1/admin/sessions/#{running}") |> json_response(422)

      assert body["error"]["code"] == "wrong_state"
    end

    @tag req: ["FR-804"]
    test "something that is not there is not found", ctx do
      assert ctx.conn |> delete(~p"/api/v1/admin/sessions/0") |> json_response(404)
      assert ctx.conn |> delete(~p"/api/v1/admin/teams/0") |> json_response(404)
    end

    @tag req: ["FR-804"]
    test "and nobody but an Org Admin may purge anything", ctx do
      assert ctx.lead_conn
             |> delete(~p"/api/v1/admin/sessions/#{ctx.session}")
             |> json_response(403)

      assert ctx.lead_conn |> delete(~p"/api/v1/admin/teams/#{ctx.team}") |> json_response(403)
      assert Repo.get(Session, ctx.session.id)
    end
  end
end
