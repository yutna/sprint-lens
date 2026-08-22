defmodule SprintLensWeb.TeamLiveTest do
  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  # Asserts on English copy, so pin the language (FR-906 makes Thai default).
  @moduletag locale: "en"

  alias SprintLens.Actions
  alias SprintLens.Teams

  setup :register_and_log_in_user

  describe "SCR-02 Home" do
    @tag req: ["FR-103"]
    test "lists the teams you belong to", %{conn: conn, user: user} do
      team = team_with_lead(user)

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ team.name
      assert html =~ "home-team-#{team.id}"
    end

    @tag req: ["FR-917"]
    test "tells a new user what to do next instead of showing an empty page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ "You are not in a team yet"
      assert html =~ "Create your first team"
    end

    @tag req: ["FR-917"]
    test "the sessions and actions sections have designed empty states", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/home")

      assert has_element?(lv, "#home-upcoming-empty")
      assert has_element?(lv, "#home-actions-empty")
    end

    @tag req: ["FR-103"]
    test "does not list a team you are not in", %{conn: conn} do
      other = team_with_lead(insert(:user))

      {:ok, _lv, html} = live(conn, ~p"/home")

      refute html =~ other.name
    end

    # The old page told a running session from a scheduled one by asking
    # whether a date was set, which is a proxy: a retrospective that was
    # scheduled *and* is under way filed itself under "coming up".
    @tag req: ["FR-203"]
    test "a room that is open right now leads the page, and is not also in the list", %{
      conn: conn,
      user: user
    } do
      team = team_with_lead(user)
      running = active_session(team, user, %{scheduled_at: DateTime.utc_now(:second)})

      {:ok, lv, _html} = live(conn, ~p"/home")

      assert has_element?(lv, "#home-live #home-session-#{running.id}")
      refute has_element?(lv, "#home-sessions #home-session-#{running.id}")
    end

    @tag req: ["FR-203"]
    test "one nobody has started yet waits under coming up", %{conn: conn, user: user} do
      team = team_with_lead(user)
      waiting = insert(:session, team: team, facilitator: user, state: "created")

      {:ok, lv, _html} = live(conn, ~p"/home")

      assert has_element?(lv, "#home-sessions #home-session-#{waiting.id}")
      refute has_element?(lv, "#home-live")
    end

    # Across every team, not within each: someone in three teams wants the
    # soonest of all of them first, and `list_open_sessions/1` only sorts one
    # team's own. A session with no date is not urgent.
    @tag req: ["FR-203"]
    test "coming up is ordered by when, with the undated ones last", %{conn: conn, user: user} do
      team = team_with_lead(user)
      later = DateTime.add(DateTime.utc_now(:second), 5, :day)
      sooner = DateTime.add(DateTime.utc_now(:second), 1, :day)

      insert(:session, team: team, facilitator: user, state: "created", title: "Undated")

      insert(:session,
        team: team,
        facilitator: user,
        state: "created",
        scheduled_at: later,
        title: "Later"
      )

      insert(:session,
        team: team,
        facilitator: user,
        state: "created",
        scheduled_at: sooner,
        title: "Sooner"
      )

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert [_, _, _] = order = for(t <- ["Sooner", "Later", "Undated"], do: index_of(html, t))
      assert order == Enum.sort(order)
      assert html =~ "No date yet"
    end

    # The page is a list of what is waiting, and the teams are the context it
    # is waiting in — so they sit under it, except on the one day when getting
    # into a team is the whole job.
    @tag req: ["FR-917"]
    test "leads with the work and closes with the teams", %{conn: conn, user: user} do
      team_with_lead(user)

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert index_of(html, ~s(id="home-actions-panel")) <
               index_of(html, ~s(id="home-teams-panel"))
    end

    @tag req: ["FR-917"]
    test "and puts them first for someone who has none", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/home")

      assert index_of(html, ~s(id="home-teams-panel")) <
               index_of(html, ~s(id="home-actions-panel"))

      assert html =~ "Start by creating a team."
    end

    @tag req: ["FR-505"]
    test "says how much is waiting, and how much of it is late", %{conn: conn, user: user} do
      user
      |> last_weeks_retro()
      |> owes(user, "Late", DateTime.add(DateTime.utc_now(:second), -2, :day))
      |> owes(user, "Open", nil)
      |> close(user)

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ "2 things are waiting for you."
      assert html =~ "2 open, 1 past due"
    end

    @tag req: ["FR-505"]
    test "counts them plainly when none of them is late", %{conn: conn, user: user} do
      user |> last_weeks_retro() |> owes(user, "Open", nil) |> close(user)

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ "1 open item"
      refute html =~ "past due"
    end

    @tag req: ["FR-917"]
    test "and says nothing needs you when nothing does", %{conn: conn, user: user} do
      team_with_lead(user)

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ "Nothing needs you at the moment."
    end

    @tag req: ["FR-203"]
    test "an open room is announced in the subtitle too", %{conn: conn, user: user} do
      team = team_with_lead(user)
      active_session(team, user)

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ "A room is open right now."
    end

    @tag req: ["NFR-201"]
    test "requires a session" do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/home")
    end
  end

  describe "SCR-03 Team list" do
    @tag req: ["FR-101"]
    test "creating a team lands on it and makes you the lead", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/teams")

      {:ok, _lv, html} =
        lv
        |> form("#team_form", team: %{name: "Alpha", description: "Platform team"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Alpha"
      assert [team] = Teams.list_teams(user)
      assert Teams.role(user, team) == :lead
    end

    @tag req: ["FR-919"]
    test "a nameless team shows an error rather than being created", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/teams")

      html = lv |> form("#team_form", team: %{name: "  "}) |> render_submit()

      assert html =~ ~s(aria-invalid="true")
      assert Teams.list_teams(user) == []
    end

    @tag req: ["FR-919"]
    test "validates as you type", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")

      assert lv |> form("#team_form", team: %{name: ""}) |> render_change() =~
               ~s(aria-invalid="true")
    end

    @tag req: ["FR-103"]
    test "lists your teams and not other people's", %{conn: conn, user: user} do
      mine = team_with_lead(user)
      theirs = team_with_lead(insert(:user))

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ mine.name
      refute html =~ theirs.name
    end

    @tag req: ["FR-106"]
    test "marks archived teams", %{conn: conn, user: user} do
      team_with_lead(user, %{is_archived: true})

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "Archived"
    end

    @tag req: ["FR-103"]
    test "a team that wrote down what it is says so in the list", %{conn: conn, user: user} do
      team_with_lead(user, %{description: "Platform and infrastructure"})

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "Platform and infrastructure"
    end

    @tag req: ["FR-917"]
    test "has a designed empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")

      assert has_element?(lv, "#teams-empty")
    end
  end

  describe "SCR-04 Team detail" do
    setup %{user: user} do
      %{team: team_with_lead(user)}
    end

    @tag req: ["FR-102"]
    test "lists the members with their roles", %{conn: conn, team: team, user: user} do
      teammate = insert(:user, display_name: "Ploy")
      join_team(teammate, team)

      {:ok, _lv, html} = live(conn, ~p"/teams/#{team}")

      assert html =~ user.display_name
      assert html =~ "Ploy"
      assert html =~ "Lead"
    end

    @tag req: ["FR-102"]
    test "a lead adds a member by email", %{conn: conn, team: team} do
      newcomer = insert(:user)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      html =
        lv
        |> form("#add_member_form", membership: %{email: newcomer.email, role: "member"})
        |> render_submit()

      assert html =~ newcomer.display_name
      assert Teams.role(newcomer, team) == :member
    end

    @tag req: ["FR-919"]
    test "an unknown email is an error on the field, not a silent no-op", %{
      conn: conn,
      team: team
    } do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      html =
        lv
        |> form("#add_member_form", membership: %{email: "ghost@example.com"})
        |> render_submit()

      assert html =~ "no account with that address"
      assert length(Teams.list_members(team)) == 1
    end

    @tag req: ["FR-102"]
    test "a lead removes a member", %{conn: conn, team: team} do
      teammate = insert(:user)
      join_team(teammate, team)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv |> element("#remove-member-#{teammate.id}") |> render_click()

      assert Teams.role(teammate, team) == nil
    end

    @tag req: ["FR-104"]
    test "a member can leave", %{team: team} do
      member = insert(:user)
      join_team(member, team)
      member_conn = log_in_user(build_conn(), member)

      {:ok, lv, _html} = live(member_conn, ~p"/teams/#{team}")

      {:ok, _lv, _html} =
        lv |> element("#leave-team") |> render_click() |> follow_redirect(member_conn, ~p"/teams")

      assert Teams.role(member, team) == nil
    end

    @tag req: ["FR-102"]
    test "the last lead is told why they cannot leave", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert lv |> element("#leave-team") |> render_click() =~ "at least one lead"
    end

    @tag req: ["FR-105", "AI-003"]
    test "a lead changes the vote budget and the AI opt-in", %{conn: conn, team: team, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv
      |> form("#team_settings_form",
        team: %{name: team.name, default_vote_budget: "3", ai_opt_in: "true"}
      )
      |> render_submit()

      {:ok, reloaded} = Teams.fetch_team(user, team.id)
      assert reloaded.default_vote_budget == 3
      assert reloaded.ai_opt_in
    end

    @tag req: ["FR-919"]
    test "an out-of-range vote budget shows an error", %{conn: conn, team: team, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      html =
        lv
        |> form("#team_settings_form", team: %{name: team.name, default_vote_budget: "0"})
        |> render_submit()

      assert html =~ ~s(aria-invalid="true")
      {:ok, reloaded} = Teams.fetch_team(user, team.id)
      assert reloaded.default_vote_budget == 5
    end

    @tag req: ["FR-919"]
    test "validates settings as you type", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      html =
        lv
        |> form("#team_settings_form", team: %{name: "", default_vote_budget: "5"})
        |> render_change()

      assert html =~ ~s(aria-invalid="true")
    end

    @tag req: ["NFR-201"]
    test "a plain member sees no management controls at all", %{conn: _conn, team: team} do
      member = insert(:user)
      join_team(member, team)

      {:ok, lv, _html} = live(log_in_user(build_conn(), member), ~p"/teams/#{team}")

      refute has_element?(lv, "#add_member_form")
      refute has_element?(lv, "#team_settings_form")
      refute has_element?(lv, "#archive-team")
    end

    @tag req: ["FR-106"]
    test "a lead archives and restores the team", %{conn: conn, team: team, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv |> element("#archive-team") |> render_click()
      {:ok, archived} = Teams.fetch_team(user, team.id)
      assert archived.is_archived

      lv |> element("#restore-team") |> render_click()
      {:ok, restored} = Teams.fetch_team(user, team.id)
      refute restored.is_archived
    end

    @tag req: ["FR-106"]
    test "an archived team hides the member and settings forms", %{conn: conn, user: user} do
      archived = team_with_lead(user, %{is_archived: true})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{archived}")

      refute has_element?(lv, "#add_member_form")
      refute has_element?(lv, "#team_settings_form")
      assert has_element?(lv, "#restore-team")
    end

    # They used to be six buttons in this page's own header slot, which is why
    # they existed on this page and nowhere else.
    @tag req: ["FR-901"]
    test "the team's sections are navigation, not buttons on one page", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(lv, "#team-nav")

      for section <- ~w(overview sessions actions insights search templates) do
        assert has_element?(lv, "#team-#{section}-link")
      end

      refute has_element?(lv, "header .flex-none #team-actions-link")
    end

    @tag req: ["FR-901"]
    test "and the strip stays put when you follow one of them", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/actions")

      assert has_element?(lv, "#team-nav")
      assert has_element?(lv, "#team-overview-link")
    end

    @tag req: ["FR-901"]
    test "says where you are in the hierarchy", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(lv, ~s(nav[aria-label="Breadcrumb"]), "Teams")
    end

    @tag req: ["FR-106"]
    test "an archived team says so, and says what that means", %{conn: conn, user: user} do
      archived = team_with_lead(user, %{is_archived: true})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{archived}")

      assert has_element?(lv, "#team-archived-notice", "history stays readable")
    end

    @tag req: ["FR-103"]
    test "a team you do not belong to is not found", %{conn: conn} do
      theirs = team_with_lead(insert(:user))

      assert {:error, {:live_redirect, %{to: "/teams"}}} = live(conn, ~p"/teams/#{theirs}")
    end
  end

  describe "SCR-11 Templates" do
    setup %{user: user} do
      %{team: team_with_lead(user)}
    end

    @tag req: ["FR-201"]
    test "lists the five built-ins", %{conn: conn, team: team} do
      {:ok, _lv, html} = live(conn, ~p"/teams/#{team}/templates")

      for name <- ["Start-Stop-Continue", "Mad-Sad-Glad", "4Ls", "KPT", "Sailboat"] do
        assert html =~ name
      end

      assert html =~ "Built-in"
    end

    @tag req: ["FR-202"]
    test "saves a custom template with named columns", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      html =
        lv
        |> form("#template_form", %{
          "template" => %{
            "name" => "Our own",
            "columns" => %{
              "0" => %{"name" => "Good", "hint" => "What worked?"},
              "1" => %{"name" => "Bad", "hint" => ""}
            }
          }
        })
        |> render_submit()

      assert html =~ "Our own"
      assert html =~ "Good"
      assert Enum.any?(Teams.list_templates(team), &(&1.name == "Our own"))
    end

    @tag req: ["FR-202"]
    test "a single column is refused with a message about the bound", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      html =
        lv
        |> form("#template_form", %{
          "template" => %{"name" => "Too few", "columns" => %{"0" => %{"name" => "Only"}}}
        })
        |> render_submit()

      assert html =~ "at least"
      refute Enum.any?(Teams.list_templates(team), &(&1.name == "Too few"))
    end

    @tag req: ["FR-919"]
    test "keeps what was typed when validation fails", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      html =
        lv
        |> form("#template_form", %{
          "template" => %{"name" => "Draft", "columns" => %{"0" => %{"name" => "Kept"}}}
        })
        |> render_change()

      assert html =~ "Kept"
    end

    @tag req: ["FR-202"]
    test "deletes a team's own template", %{conn: conn, team: team, user: user} do
      {:ok, template} =
        Teams.create_template(user, team, %{
          name: "Doomed",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      lv |> element("#delete-template-#{template.id}") |> render_click()

      refute Enum.any?(Teams.list_templates(team), &(&1.id == template.id))
    end

    @tag req: ["FR-201"]
    test "offers no delete control for a built-in", %{conn: conn, team: team} do
      builtin = hd(Teams.list_builtin_templates())

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      refute has_element?(lv, "#delete-template-#{builtin.id}")
    end

    @tag req: ["FR-201"]
    test "refuses a delete aimed at a built-in even if the control is forged", %{
      conn: conn,
      team: team
    } do
      builtin = hd(Teams.list_builtin_templates())

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      assert render_click(lv, "delete", %{"id" => builtin.id}) =~ "cannot be changed"
      assert Enum.any?(Teams.list_builtin_templates(), &(&1.id == builtin.id))
    end

    @tag req: ["NFR-201"]
    test "refuses a delete aimed at another team's template", %{conn: conn, team: team} do
      other_lead = insert(:user)
      other_team = team_with_lead(other_lead)

      {:ok, theirs} =
        Teams.create_template(other_lead, other_team, %{
          name: "Theirs",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      render_click(lv, "delete", %{"id" => theirs.id})

      assert {:ok, _still_there} = Teams.fetch_template(other_team, theirs.id)
    end

    @tag req: ["FR-106"]
    test "an archived team offers no template form", %{conn: conn, user: user} do
      archived = team_with_lead(user, %{is_archived: true})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{archived}/templates")

      refute has_element?(lv, "#template_form")
    end

    @tag req: ["FR-103"]
    test "another team's templates page is not found", %{conn: conn} do
      theirs = team_with_lead(insert(:user))

      assert {:error, {:live_redirect, %{to: "/teams"}}} =
               live(conn, ~p"/teams/#{theirs}/templates")
    end

    @tag req: ["FR-202"]
    test "a submission with no column inputs at all is refused", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      assert render_submit(lv, "save", %{"template" => %{"name" => "Bare"}}) =~ "at least"
    end

    @tag req: ["FR-202"]
    test "a hint typed with no column name is kept and then rejected", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      html =
        render_submit(lv, "save", %{
          "template" => %{
            "name" => "Orphan",
            "columns" => %{
              "0" => %{"name" => "Good", "hint" => ""},
              # No "name" key at all, which is what a browser sends for a row
              # the person never touched the first input of.
              "1" => %{"hint" => "I forgot the name"}
            }
          }
        })

      assert html =~ "every column needs a name"
      refute Enum.any?(Teams.list_templates(team), &(&1.name == "Orphan"))
    end

    @tag req: ["FR-202"]
    test "a column sent without a hint key is accepted", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/templates")

      render_submit(lv, "save", %{
        "template" => %{
          "name" => "Hintless",
          "columns" => %{"0" => %{"name" => "A"}, "1" => %{"name" => "B"}}
        }
      })

      assert Enum.any?(Teams.list_templates(team), &(&1.name == "Hintless"))
    end
  end

  describe "hiding a control is not the security boundary (NFR-201)" do
    setup do
      lead = insert(:user)
      team = team_with_lead(lead)
      member = insert(:user)
      join_team(member, team)

      %{team: team, member_conn: log_in_user(build_conn(), member), lead: lead, member: member}
    end

    @tag req: ["NFR-201", "FR-105"]
    test "a member firing the settings event is refused", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")

      html =
        render_submit(lv, "save_settings", %{
          "team" => %{"name" => "Hijacked", "ai_opt_in" => "true"}
        })

      assert html =~ "do not have permission"
      assert {:ok, unchanged} = Teams.fetch_team(ctx.lead, ctx.team.id)
      assert unchanged.name == ctx.team.name
    end

    @tag req: ["NFR-201", "FR-102"]
    test "a member firing the add-member event is refused", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")
      outsider = insert(:user)

      html =
        render_submit(lv, "add_member", %{
          "membership" => %{"email" => outsider.email, "role" => "lead"}
        })

      assert html =~ "do not have permission"
      assert Teams.role(outsider, ctx.team) == nil
    end

    @tag req: ["NFR-201", "FR-102"]
    test "a member firing the remove-member event is refused", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")

      html = render_click(lv, "remove_member", %{"user-id" => to_string(ctx.lead.id)})

      assert html =~ "do not have permission"
      assert Teams.role(ctx.lead, ctx.team) == :lead
    end

    @tag req: ["NFR-201", "FR-106"]
    test "a member firing archive or restore is refused", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")

      assert render_click(lv, "archive", %{}) =~ "do not have permission"
      assert render_click(lv, "restore", %{}) =~ "do not have permission"
      assert {:ok, unchanged} = Teams.fetch_team(ctx.lead, ctx.team.id)
      refute unchanged.is_archived
    end

    @tag req: ["NFR-201", "FR-102"]
    test "removing someone who is not in the team says so", ctx do
      lead_conn = log_in_user(build_conn(), ctx.lead)
      {:ok, lv, _html} = live(lead_conn, ~p"/teams/#{ctx.team}")

      html = render_click(lv, "remove_member", %{"user-id" => to_string(insert(:user).id)})

      assert html =~ "does not exist"
    end

    @tag req: ["NFR-201", "FR-202"]
    test "a member of an archived team cannot save a template", %{lead: lead} do
      archived = team_with_lead(lead, %{is_archived: true})
      {:ok, lv, _html} = live(log_in_user(build_conn(), lead), ~p"/teams/#{archived}/templates")

      html =
        render_submit(lv, "save", %{
          "template" => %{
            "name" => "Sneaky",
            "columns" => %{"0" => %{"name" => "A"}, "1" => %{"name" => "B"}}
          }
        })

      assert html =~ "do not have permission"
      refute Enum.any?(Teams.list_templates(archived), &(&1.name == "Sneaky"))
    end
  end

  describe "SCR-02 Home with an archived team" do
    @tag req: ["FR-106"]
    test "marks it as archived", %{conn: conn, user: user} do
      team_with_lead(user, %{is_archived: true})

      {:ok, _lv, html} = live(conn, ~p"/home")

      assert html =~ "Archived"
    end
  end

  # A retrospective that has been and gone, which is where an outstanding
  # commitment comes from. Actions can only be written while a room is open,
  # so the room is opened, used, and closed again.
  defp last_weeks_retro(user) do
    team = team_with_lead(user)

    active_session(team, user, %{phase: "discuss"})
  end

  defp owes(session, user, title, due_date) do
    {:ok, _item} =
      Actions.create_action(user, session, %{
        title: title,
        assignee_id: user.id,
        due_date: due_date
      })

    session
  end

  defp close(session, user) do
    {:ok, closed} = SprintLens.Retro.close_session(user, session)

    closed
  end

  # Document order, which is the whole point of several of these assertions.
  defp index_of(html, needle) do
    case :binary.match(html, needle) do
      {at, _length} -> at
      :nomatch -> flunk("#{needle} is not on the page")
    end
  end
end
