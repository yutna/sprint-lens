defmodule SprintLensWeb.Api.V1.ExportApiTest do
  @moduledoc """
  Downloading a recap (§7.2, FR-701 to FR-703).

  Two things are checked besides the formats themselves: an export is a
  download, so it carries the headers a browser needs to save a file; and it
  goes through the same closed-and-yours check the recap page does, because an
  export of a live session would be one more way around blind mode.
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
    conn |> put_req_header("authorization", "Bearer " <> Accounts.create_api_token(user))
  end

  defp played(ctx, attrs \\ %{}) do
    {:ok, session} =
      Retro.create_session(ctx.facilitator, ctx.team, Map.merge(%{title: "Sprint 12"}, attrs))

    {:ok, session} = Retro.start_session(ctx.facilitator, session)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    {:ok, card} =
      Board.create_card(ctx.participant, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, discussing} = Retro.set_phase(ctx.facilitator, session, :discuss)

    {:ok, _note} =
      Board.write_note(ctx.facilitator, discussing, {:card, card.id}, "Fix the build")

    {:ok, _action} =
      Actions.create_action(ctx.participant, discussing, %{title: "Write the runbook"})

    {:ok, closed} = Retro.close_session(ctx.facilitator, discussing)

    %{session: closed, card: card}
  end

  describe "GET /api/v1/sessions/:id/export" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-701"]
    test "markdown by default, as a file the browser will save", ctx do
      conn = get(ctx.participant_conn, ~p"/api/v1/sessions/#{ctx.session}/export")

      assert conn.status == 200
      assert response_content_type(conn, :md) =~ "text/markdown"

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~s(attachment; filename="sprint-12-#{ctx.session.id}.md")

      body = response(conn, 200)
      assert body =~ "# Sprint 12"
      assert body =~ "- Deploys are slow"
      assert body =~ "Fix the build"
    end

    @tag req: ["FR-702"]
    test "the cards as CSV", ctx do
      conn = get(ctx.conn, ~p"/api/v1/sessions/#{ctx.session}/export?format=csv")

      assert response_content_type(conn, :csv) =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "cards.csv"

      body = response(conn, 200)
      assert body =~ "id,column,text,author,created_at"
      assert body =~ "Deploys are slow"
    end

    @tag req: ["FR-702"]
    test "and the action items as their own CSV", ctx do
      conn = get(ctx.conn, ~p"/api/v1/sessions/#{ctx.session}/export?format=csv&of=actions")

      body = response(conn, 200)

      assert get_resp_header(conn, "content-disposition") |> hd() =~ "actions.csv"
      assert body =~ "Write the runbook"
      refute body =~ "Deploys are slow"
    end

    @tag req: ["FR-703"]
    test "the whole session as JSON", ctx do
      conn = get(ctx.conn, ~p"/api/v1/sessions/#{ctx.session}/export?format=json")

      assert response_content_type(conn, :json) =~ "application/json"

      data = conn |> response(200) |> Jason.decode!()

      assert data["session"]["title"] == "Sprint 12"
      assert data["session"]["participant_count"] == 1
      assert [%{"text" => "Deploys are slow"}] = data["cards"]
      assert [%{"body" => "Fix the build"}] = data["notes"]
      assert [%{"title" => "Write the runbook"}] = data["actions"]
    end

    @tag req: ["FR-701"]
    test "a format nobody offers is refused, with the ones that exist", ctx do
      conn =
        ctx.conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/sessions/#{ctx.session}/export?format=pdf")

      body = json_response(conn, 422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["format"] == ["markdown", "csv", "json"]
    end

    @tag req: ["FR-702"]
    test "and so is a CSV of something that is not cards or actions", ctx do
      conn =
        ctx.conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/sessions/#{ctx.session}/export?format=csv&of=votes")

      assert json_response(conn, 422)["error"]["details"]["of"] == ["cards", "actions"]
    end

    @tag req: ["FR-906", "FR-701"]
    test "a Thai title survives the download header", ctx do
      %{session: thai} = played(ctx, %{title: "รีโทรสปรินต์ 12"})

      conn = get(ctx.conn, ~p"/api/v1/sessions/#{thai}/export")

      [disposition] = get_resp_header(conn, "content-disposition")

      # RFC 6266: an ASCII fallback for old clients, and the real name in
      # `filename*` for everybody else.
      assert disposition =~ ~s(filename=")
      assert disposition =~ "filename*=UTF-8''"
      assert disposition =~ URI.encode("รีโทรสปรินต์")
    end

    @tag req: ["FR-209", "FR-703"]
    test "a session still running cannot be exported", ctx do
      {:ok, live} = Retro.create_session(ctx.facilitator, ctx.team, %{title: "L", is_blind: true})
      {:ok, live} = Retro.start_session(ctx.facilitator, live)

      conn =
        ctx.conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/sessions/#{live}/export?format=json")

      assert json_response(conn, 404)
    end

    @tag req: ["FR-103"]
    test "and a stranger exports nothing", %{conn: conn} = ctx do
      stranger =
        conn
        |> authed(insert(:user, language: "en"))
        |> put_req_header("accept", "application/json")

      assert stranger |> get(~p"/api/v1/sessions/#{ctx.session}/export") |> json_response(404)
    end

    @tag req: ["FR-210", "FR-703"]
    test "an anonymous session exports nobody's name", ctx do
      %{session: anonymous} = played(ctx, %{is_anonymous: true})

      for format <- ~w(markdown csv json) do
        body =
          ctx.conn
          |> get(~p"/api/v1/sessions/#{anonymous}/export?format=#{format}")
          |> response(200)

        refute body =~ "Ploy"
      end
    end
  end

  describe "the browser download" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-701"]
    test "the same export is reachable from a signed-in session", %{conn: _api} = ctx do
      conn = build_conn() |> log_in_user(ctx.participant)

      conn = get(conn, ~p"/sessions/#{ctx.session}/export?format=markdown")

      assert conn.status == 200
      assert response(conn, 200) =~ "# Sprint 12"
    end

    @tag req: ["FR-103"]
    test "and not from somebody else's, who gets a page rather than a crash", ctx do
      conn = build_conn() |> log_in_user(insert(:user, language: "en"))

      conn = get(conn, ~p"/sessions/#{ctx.session}/export")

      assert redirected_to(conn) == ~p"/home"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "does not exist"
    end

    @tag req: ["FR-919"]
    test "and a format nobody offers is a page too", ctx do
      conn = build_conn() |> log_in_user(ctx.participant)

      conn = get(conn, ~p"/sessions/#{ctx.session}/export?format=pdf")

      assert redirected_to(conn) == ~p"/home"
    end
  end
end
