defmodule SprintLensWeb.InsightsLiveTest do
  @moduledoc """
  The archive, the recap, the dashboard and search on screen (SCR-08, SCR-09,
  FR-601 to FR-606).

  The assertions that matter most are the ones about absence: an anonymous
  session's recap must contain no name for any viewer, and the org-wide view
  must contain no card text at all.
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.SessionServer

  setup :register_and_log_in_user

  setup %{user: user} do
    team = team_with_lead(user)
    participant = insert(:user, language: "en", display_name: "Ploy")
    join_team(participant, team)

    %{
      team: team,
      facilitator: user,
      participant: participant,
      participant_conn: log_in_user(build_conn(), participant)
    }
  end

  defp played(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.facilitator, attrs)
    on_exit(fn -> SessionServer.stop(session.id) end)

    # Both people answer, so the participant count is two and the
    # participation rate is the whole team (FR-601, FR-604).
    {:ok, _mood} = Board.record_mood(ctx.participant, session, :checkin_mood, 4)
    {:ok, _mood} = Board.record_mood(ctx.facilitator, session, :checkin_mood, 4)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)
    column = hd(session.columns)

    {:ok, card} =
      Board.create_card(ctx.participant, session, %{
        column_id: column.id,
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

  describe "SCR-08 the recap (FR-602)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-602"]
    test "shows the board, the discussion and what was agreed", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}/recap")

      assert has_element?(lv, "#recap-card-#{ctx.card.id}", "Deploys are slow")
      assert has_element?(lv, "#recap-topic-card-#{ctx.card.id}", "Fix the build first")
      assert has_element?(lv, "#action-#{ctx.action.id}", "Write the runbook")
      assert has_element?(lv, "#recap-participants", "2")
      assert has_element?(lv, "#recap-card-count", "1")
      assert has_element?(lv, "#recap-mood", "4")
    end

    @tag req: ["FR-404", "FR-602"]
    test "the vote totals are visible, because closing revealed them", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}/recap")

      assert has_element?(lv, "#recap-topic-card-#{ctx.card.id}", "1 vote")
    end

    @tag req: ["FR-602"]
    test "is read-only: nothing on it changes anything", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}/recap")

      html = render(lv)

      refute html =~ "phx-submit"

      refute has_element?(
               lv,
               "[phx-click]:not([phx-click*='set_'])" <> ":not([phx-click*='lv:'])"
             )
    end

    @tag req: ["FR-602"]
    test "a session that is still running has no recap", ctx do
      running = active_session(ctx.team, ctx.facilitator)
      on_exit(fn -> SessionServer.stop(running.id) end)

      assert {:error, {:live_redirect, %{to: "/home"}}} =
               live(ctx.conn, ~p"/sessions/#{running}/recap")
    end

    @tag req: ["FR-103"]
    test "and a team you are not in has none for you", ctx do
      stranger = log_in_user(build_conn(), insert(:user, language: "en"))

      assert {:error, {:live_redirect, %{to: "/home"}}} =
               live(stranger, ~p"/sessions/#{ctx.session}/recap")
    end
  end

  describe "the recap of an anonymous session (FR-210, FR-606)" do
    setup ctx, do: Map.merge(ctx, played(ctx, %{is_anonymous: true}))

    @tag req: ["FR-210", "FR-606"]
    test "carries no name, for any viewer including an Org Admin", ctx do
      admin = insert(:org_admin, language: "en")
      join_team(admin, ctx.team)

      for conn <- [ctx.conn, ctx.participant_conn, log_in_user(build_conn(), admin)] do
        {:ok, lv, _html} = live(conn, ~p"/sessions/#{ctx.session}/recap")

        # Scoped to the content, the way the Playwright privacy specs already
        # scope theirs. One of these viewers is Ploy, and the account menu
        # shows a person their own name — which reveals nothing. What FR-210
        # forbids is a card leading back to whoever wrote it, and that is a
        # claim about the recap, not about the chrome around it.
        html = lv |> element("main") |> render()

        assert html =~ "Deploys are slow"
        refute html =~ "Ploy"
      end
    end
  end

  describe "a recap with nothing in it" do
    @tag req: ["FR-917"]
    test "says so rather than showing empty headings", ctx do
      quiet = active_session(ctx.team, ctx.facilitator)
      on_exit(fn -> SessionServer.stop(quiet.id) end)
      {:ok, closed} = Retro.close_session(ctx.facilitator, quiet)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{closed}/recap")

      assert has_element?(lv, "#recap-topics-empty")
      assert has_element?(lv, "#recap-actions-empty")
      assert has_element?(lv, "#recap-participants", "0")
    end

    @tag req: ["FR-602"]
    test "a cluster in the recap names the cards it holds", ctx do
      session = active_session(ctx.team, ctx.facilitator)
      on_exit(fn -> SessionServer.stop(session.id) end)
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

      cards =
        for text <- ["Deploys are slow", "Flaky CI"] do
          {:ok, card} =
            Board.create_card(ctx.participant, brainstorming, %{
              column_id: hd(session.columns).id,
              text: text
            })

          card
        end

      {:ok, grouping} = Retro.set_phase(ctx.facilitator, brainstorming, :group)

      {:ok, group} =
        Board.create_group(ctx.participant, grouping, "Tooling", Enum.map(cards, & &1.id))

      {:ok, closed} = Retro.close_session(ctx.facilitator, grouping)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{closed}/recap")

      assert has_element?(lv, "#recap-topic-group-#{group.id}", "Tooling")
      assert has_element?(lv, "#recap-topic-group-#{group.id}", "Flaky CI")
    end
  end

  describe "the archive (FR-601)" do
    @tag req: ["FR-601"]
    test "lists finished retrospectives with what happened in them", ctx do
      %{session: closed} = played(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert has_element?(lv, "#archive-#{closed.id}", closed.title)
      assert has_element?(lv, "#archive-participants-#{closed.id}", "2")
      assert has_element?(lv, "#archive-cards-#{closed.id}", "1")
      assert has_element?(lv, "#archive-mood-#{closed.id}", "4")
    end

    @tag req: ["FR-601"]
    test "names the template, and says when a session was anonymous", ctx do
      template = insert(:template, team: ctx.team, name: "Sailboat")
      %{session: closed} = played(ctx, %{template_id: template.id, is_anonymous: true})

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert has_element?(lv, "#archive-#{closed.id}", "Sailboat")
      assert has_element?(lv, "#archive-#{closed.id}", "Anonymous")
    end

    @tag req: ["FR-917"]
    test "and says so when nothing has finished", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert has_element?(lv, "#archive-empty")
    end

    @tag req: ["FR-602"]
    test "a closed session in the list leads to its recap, not its board", ctx do
      %{session: closed} = played(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/sessions")

      assert lv
             |> element("#session-#{closed.id} a")
             |> render()
             |> String.contains?("/sessions/#{closed.id}/recap")
    end
  end

  describe "SCR-09 the dashboard (FR-604)" do
    @tag req: ["FR-604"]
    test "draws a point per finished session", ctx do
      %{session: first} = played(ctx)
      %{session: second} = played(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/insights")

      for id <- [first.id, second.id] do
        assert has_element?(lv, "#mood-trend-#{id}")
        assert has_element?(lv, "#cards-trend-#{id}")
        assert has_element?(lv, "#participation-trend-#{id}")
      end

      assert has_element?(lv, "#mood-trend-#{first.id}", "4")
      assert has_element?(lv, "#participation-trend-#{first.id}", "100.0%")
    end

    @tag req: ["FR-506", "FR-604"]
    test "and how the team's actions are doing", ctx do
      played(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/insights")

      assert has_element?(lv, "#insight-open", "1")
      assert has_element?(lv, "#insight-completion", "0")
    end

    @tag req: ["FR-604"]
    test "a session nobody rated leaves a gap rather than a zero", ctx do
      quiet = active_session(ctx.team, ctx.facilitator)
      on_exit(fn -> SessionServer.stop(quiet.id) end)
      {:ok, closed} = Retro.close_session(ctx.facilitator, quiet)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/insights")

      assert has_element?(lv, "#mood-trend-#{closed.id}", "—")
    end

    @tag req: ["FR-917"]
    test "a team with no history says so", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/insights")

      assert has_element?(lv, "#insights-empty")
    end

    @tag req: ["FR-103"]
    test "and a team you are not in has no dashboard", ctx do
      theirs = team_with_lead(insert(:user))

      assert {:error, {:live_redirect, %{to: "/teams"}}} =
               live(ctx.conn, ~p"/teams/#{theirs}/insights")
    end
  end

  describe "the org-wide view (FR-605)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-605"]
    test "an Org Admin sees a row of numbers per team", ctx do
      admin = insert(:org_admin, language: "en")
      join_team(admin, ctx.team)

      {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/teams/#{ctx.team}/insights")

      assert has_element?(lv, "#org-insights")
      assert has_element?(lv, "#org-team-#{ctx.team.id}", ctx.team.name)
    end

    @tag req: ["FR-605"]
    test "and nothing anybody wrote, nor anybody's name", ctx do
      admin = insert(:org_admin, language: "en")
      join_team(admin, ctx.team)

      {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/teams/#{ctx.team}/insights")

      html = lv |> element("#org-insights") |> render()

      refute html =~ "Deploys are slow"
      refute html =~ "Fix the build first"
      refute html =~ "Write the runbook"
      refute html =~ "Ploy"
    end

    @tag req: ["FR-605"]
    test "and nobody else sees the section at all", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/insights")

      refute has_element?(lv, "#org-insights")
    end
  end

  describe "search (FR-603)" do
    setup ctx, do: Map.merge(ctx, played(ctx))

    @tag req: ["FR-603"]
    test "finds a card, a note and an action", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/teams/#{ctx.team}/search")

      assert has_element?(lv, "#search-prompt")

      lv |> form("#search-form") |> render_change(%{"search" => %{"q" => "the"}})

      assert has_element?(lv, "#search-notes", "Fix the build first")
      assert has_element?(lv, "#search-actions", "Write the runbook")
    end

    @tag req: ["FR-603"]
    test "a card links to the recap it came from", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/teams/#{ctx.team}/search")

      lv |> form("#search-form") |> render_change(%{"search" => %{"q" => "deploys"}})

      assert has_element?(lv, "#search-card-#{ctx.card.id}", "Deploys are slow")

      assert lv
             |> element("#search-card-#{ctx.card.id} a")
             |> render()
             |> String.contains?("/sessions/#{ctx.session.id}/recap")
    end

    @tag req: ["FR-603"]
    test "nothing matching says so, with what was asked for", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/teams/#{ctx.team}/search")

      lv |> form("#search-form") |> render_change(%{"search" => %{"q" => "zzz"}})

      assert has_element?(lv, "#search-empty", "zzz")
    end

    @tag req: ["FR-603"]
    test "an empty box goes back to the prompt", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/teams/#{ctx.team}/search")

      lv |> form("#search-form") |> render_change(%{"search" => %{"q" => "deploys"}})
      assert has_element?(lv, "#search-cards")

      lv |> form("#search-form") |> render_change(%{"search" => %{"q" => "  "}})
      assert has_element?(lv, "#search-prompt")
    end

    @tag req: ["FR-103"]
    test "and a team you are not in has no search", ctx do
      theirs = team_with_lead(insert(:user))

      assert {:error, {:live_redirect, %{to: "/teams"}}} =
               live(ctx.conn, ~p"/teams/#{theirs}/search")
    end
  end
end
