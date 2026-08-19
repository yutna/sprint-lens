defmodule SprintLensWeb.AdminLiveTest do
  @moduledoc """
  SCR-12 on screen (FR-801 to FR-807).

  Everything destructive here is tested twice: once that it works, and once
  that somebody who is not an Org Admin cannot reach it — including by
  pushing the event straight at the socket, which is the only version of
  "cannot" that matters (NFR-201).
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Accounts.User
  alias SprintLens.Admin
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer
  alias SprintLens.Teams
  alias SprintLens.Teams.Team

  setup :register_and_log_in_user

  setup %{user: user, conn: conn} do
    {:ok, admin} = SprintLens.Accounts.set_org_admin(user, true)

    lead = insert(:user, language: "en", display_name: "Lek")
    team = team_with_lead(lead)
    member = insert(:user, language: "en", display_name: "Ploy")
    join_team(member, team)

    %{
      conn: conn,
      admin: admin,
      lead: lead,
      member: member,
      team: team,
      member_conn: log_in_user(build_conn(), member)
    }
  end

  defp played(ctx) do
    session = active_session(ctx.team, ctx.lead)
    on_exit(fn -> SessionServer.stop(session.id) end)
    {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)

    {:ok, card} =
      Board.create_card(ctx.member, session, %{
        column_id: hd(session.columns).id,
        text: "Deploys are slow"
      })

    {:ok, closed} = Retro.close_session(ctx.lead, session)

    %{session: closed, card: card}
  end

  describe "who may open it (FR-801)" do
    @tag req: ["FR-801"]
    test "an Org Admin sees the page", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      assert has_element?(lv, "#admin-users")
      assert has_element?(lv, "#org_settings_form")
      assert has_element?(lv, "#audit-empty")
    end

    @tag req: ["FR-801"]
    test "and nobody else gets past the door", ctx do
      assert {:error, {:live_redirect, %{to: "/home"}}} = live(ctx.member_conn, ~p"/admin")
    end
  end

  describe "settings and the kill switches (FR-802, FR-806)" do
    @tag req: ["FR-802"]
    test "an Org Admin changes them from the form", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      html =
        lv
        |> form("#org_settings_form",
          settings: %{
            default_language: "en",
            default_vote_budget: 7,
            retention_days: 90,
            ai_enabled: "true",
            webhooks_enabled: "true"
          }
        )
        |> render_submit()

      assert html =~ "Settings saved"
      assert Admin.settings().retention_days == 90
      assert Admin.settings().default_language == "en"
    end

    @tag req: ["FR-806"]
    test "and switches AI or webhooks off", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      lv
      |> form("#org_settings_form",
        settings: %{
          default_language: "th",
          default_vote_budget: 5,
          retention_days: 365,
          ai_enabled: "false",
          webhooks_enabled: "false"
        }
      )
      |> render_submit()

      refute Admin.ai_enabled?()
      refute Admin.webhooks_enabled?()
    end

    @tag req: ["FR-802"]
    test "a setting that makes no sense is reported rather than saved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      html =
        lv
        |> form("#org_settings_form",
          settings: %{default_language: "th", default_vote_budget: 5, retention_days: 1}
        )
        |> render_submit()

      assert html =~ "greater than or equal to 30"
      assert Admin.settings().retention_days == 365
    end
  end

  describe "people (FR-801, FR-005)" do
    @tag req: ["FR-801"]
    test "the list names everybody, and says who is what", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      assert has_element?(lv, "#admin-user-#{ctx.member.id}", "Ploy")
      assert has_element?(lv, "#admin-user-#{ctx.admin.id}", "Org Admin")
    end

    @tag req: ["FR-005"]
    test "somebody can be deactivated and let back in", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      lv |> element("#deactivate-#{ctx.member.id}") |> render_click()

      assert has_element?(lv, "#admin-inactive-#{ctx.member.id}")

      lv |> element("#reactivate-#{ctx.member.id}") |> render_click()

      refute has_element?(lv, "#admin-inactive-#{ctx.member.id}")
    end

    @tag req: ["FR-801"]
    test "but not while they are a team's only lead, and it says so", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      html = lv |> element("#deactivate-#{ctx.lead.id}") |> render_click()

      assert html =~ "Reassign leadership"
      refute has_element?(lv, "#admin-inactive-#{ctx.lead.id}")
    end

    @tag req: ["FR-801"]
    test "leadership can be handed to somebody else", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      html =
        lv
        |> form("#leadership_form",
          leadership: %{team_id: ctx.team.id, user_id: ctx.member.id}
        )
        |> render_submit()

      assert html =~ "Leadership reassigned"
      assert Teams.role(ctx.member, ctx.team) == :lead
    end

    @tag req: ["FR-805"]
    test "and somebody can be erased", ctx do
      %{card: card} = played(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      lv |> element("#erase-#{ctx.member.id}") |> render_click()

      assert has_element?(lv, "#admin-erased-#{ctx.member.id}")
      refute render(lv) =~ "Ploy"
      assert Repo.get(Card, card.id).author_id == nil
    end

    @tag req: ["NFR-201"]
    test "a forged event from a member changes nothing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      # The page refuses to mount for a member (tested above), so the forged
      # push has to come from a socket that is allowed to exist — an admin's,
      # aimed at something that is not there.
      assert render_click(lv, "deactivate", %{"id" => "0"}) =~ "does not exist"
      assert render_click(lv, "erase", %{"id" => "0"}) =~ "does not exist"
      assert render_click(lv, "reactivate", %{"id" => "0"}) =~ "does not exist"
      assert %User{is_active: true} = Repo.get(User, ctx.member.id)
    end
  end

  describe "rights taken away while the page is open (NFR-201)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["NFR-201"]
    test "an admin who stops being one is refused by every control", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      # Mounting decided once; the socket outlives that decision, so the
      # context has to decide again for every event.
      {:ok, _demoted} = SprintLens.Accounts.set_org_admin(ctx.admin, false)

      assert render_click(lv, "deactivate", %{"id" => to_string(ctx.member.id)}) =~ "permission"

      assert render_click(lv, "purge_session", %{"id" => to_string(ctx.session.id)}) =~
               "permission"

      assert render_click(lv, "purge_team", %{"id" => to_string(ctx.team.id)}) =~ "permission"

      assert render_submit(lv, "save_settings", %{
               "settings" => %{
                 "default_language" => "en",
                 "default_vote_budget" => "5",
                 "retention_days" => "90"
               }
             }) =~ "permission"

      assert render_submit(lv, "reassign", %{
               "leadership" => %{
                 "team_id" => to_string(ctx.team.id),
                 "user_id" => to_string(ctx.member.id)
               }
             }) =~ "permission"

      assert Repo.get(Session, ctx.session.id)
      assert Admin.settings().retention_days == 365
    end
  end

  describe "purging (FR-804)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-804"]
    test "a finished retrospective can be purged from the page", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      assert has_element?(lv, "#admin-session-#{ctx.session.id}")

      html = lv |> element("#purge-session-#{ctx.session.id}") |> render_click()

      assert html =~ "purged"
      assert Repo.get(Session, ctx.session.id) == nil
    end

    @tag req: ["FR-804"]
    test "and a whole team", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      lv |> element("#purge-team-#{ctx.team.id}") |> render_click()

      assert Repo.get(Team, ctx.team.id) == nil
      refute has_element?(lv, "#admin-team-#{ctx.team.id}")
    end

    @tag req: ["FR-804"]
    test "every purge control asks first", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      for id <- ["#purge-session-#{ctx.session.id}", "#purge-team-#{ctx.team.id}"] do
        assert lv |> element(id) |> render() =~ "data-confirm"
      end

      assert lv |> element("#erase-#{ctx.member.id}") |> render() =~ "data-confirm"
    end

    @tag req: ["FR-804"]
    test "a session still running is not offered, and is refused if asked for", ctx do
      running = active_session(ctx.team, ctx.lead)
      on_exit(fn -> SessionServer.stop(running.id) end)

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      refute has_element?(lv, "#purge-session-#{running.id}")

      assert render_click(lv, "purge_session", %{"id" => to_string(running.id)}) =~
               "Close the retrospective"

      assert Repo.get(Session, running.id)
    end

    @tag req: ["NFR-201"]
    test "and something that is not there is not purged", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      assert render_click(lv, "purge_session", %{"id" => "0"}) =~ "does not exist"
      assert render_click(lv, "purge_team", %{"id" => "0"}) =~ "does not exist"

      assert render_click(lv, "reassign", %{"leadership" => %{"team_id" => "0", "user_id" => "0"}}) =~
               "does not exist"
    end
  end

  describe "the audit log on screen (FR-807)" do
    @tag req: ["FR-807"]
    test "shows what has been done, newest first", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      lv |> element("#deactivate-#{ctx.member.id}") |> render_click()

      assert has_element?(lv, "#audit-events", "user.deactivated")
      assert has_element?(lv, "#audit-events", "user:#{ctx.member.id}")
      assert has_element?(lv, "#audit-events", ctx.admin.display_name)
    end

    @tag req: ["FR-807"]
    test "and says the machine did the ones nobody asked for", ctx do
      {:ok, _event} = Admin.record_event(:system, "session.purged", "session:7")

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin")

      assert has_element?(lv, "#audit-events", "system")
    end
  end
end
