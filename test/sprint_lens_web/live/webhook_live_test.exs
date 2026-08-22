defmodule SprintLensWeb.WebhookLiveTest do
  @moduledoc """
  The webhook section of SCR-04 (FR-704, FR-706).

  The assertion this module exists for is that the stored secret is never
  rendered back. Everything else on the page can be read from the screen; a
  shared secret that appears on every render has a much larger surface than
  the one save that set it.
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Webhooks
  alias SprintLens.Webhooks.Subscription
  alias SprintLens.Workers.WebhookDelivery

  setup :register_and_log_in_user

  setup %{user: user} do
    team = team_with_lead(user)
    member = insert(:user, language: "en", display_name: "Ploy")
    join_team(member, team)

    %{team: team, lead: user, member: member, member_conn: log_in_user(build_conn(), member)}
  end

  defp save(lv, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "url" => "https://hooks.example.com/sprintlens",
          "secret" => "a-secret-long-enough",
          "events" => ["session.started", "session.closed"],
          "is_active" => "true"
        },
        attrs
      )

    render_submit(lv, "save_webhook", %{"webhook" => params})
  end

  describe "configuring the webhook (FR-704)" do
    @tag req: ["FR-704"]
    test "a lead sets one up from the team page", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      assert has_element?(lv, "#webhook_form")
      assert save(lv) =~ "Webhook saved"

      subscription = Webhooks.get_subscription(ctx.team)
      assert subscription.url == "https://hooks.example.com/sprintlens"
      assert Subscription.subscribed(subscription) == [:"session.started", :"session.closed"]
    end

    @tag req: ["FR-705"]
    test "the stored secret is never rendered back", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
      save(lv, %{"secret" => "the-real-shared-secret"})

      {:ok, reloaded, html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      refute html =~ "the-real-shared-secret"
      refute render(reloaded) =~ "the-real-shared-secret"
    end

    @tag req: ["FR-705"]
    test "and leaving the box blank keeps the one already saved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
      save(lv, %{"secret" => "the-real-shared-secret"})

      save(lv, %{"secret" => "", "url" => "https://elsewhere.example.com/hook"})

      subscription = Webhooks.get_subscription(ctx.team)
      assert subscription.url == "https://elsewhere.example.com/hook"
      assert subscription.secret == "the-real-shared-secret"
    end

    @tag req: ["FR-704"]
    test "a bad address is reported rather than saved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      assert save(lv, %{"url" => "not a url"}) =~ "http"
      assert Webhooks.get_subscription(ctx.team) == nil
    end

    @tag req: ["FR-704"]
    test "it can be switched off without being removed", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
      save(lv)
      save(lv, %{"is_active" => "false"})

      subscription = Webhooks.get_subscription(ctx.team)
      refute subscription.is_active
    end

    @tag req: ["FR-704"]
    test "or removed altogether", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
      save(lv)

      lv |> element("#delete-webhook") |> render_click()

      assert Webhooks.get_subscription(ctx.team) == nil
      refute has_element?(lv, "#delete-webhook")
    end

    @tag req: ["FR-704"]
    test "a member sees no webhook section at all", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")

      refute has_element?(lv, "#webhook_form")
      refute has_element?(lv, "#deliveries")
    end

    @tag req: ["NFR-201"]
    test "and a forged save from a member is refused", ctx do
      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")

      assert save(lv) =~ "permission"
      assert Webhooks.get_subscription(ctx.team) == nil
    end

    @tag req: ["NFR-201"]
    test "as is a forged removal", ctx do
      {:ok, lead_lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
      save(lead_lv)

      {:ok, lv, _html} = live(ctx.member_conn, ~p"/teams/#{ctx.team}")

      assert render_click(lv, "delete_webhook", %{}) =~ "permission"
      assert Webhooks.get_subscription(ctx.team)
    end

    @tag req: ["FR-704"]
    test "removing one that is already gone is quietly fine", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      assert render_click(lv, "delete_webhook", %{})
      assert Webhooks.get_subscription(ctx.team) == nil
    end
  end

  describe "the delivery log (FR-706)" do
    setup ctx do
      {:ok, subscription} =
        Webhooks.configure(ctx.lead, ctx.team, %{
          url: "https://hooks.example.com/sprintlens",
          secret: "a-secret-long-enough",
          events: ["session.closed"]
        })

      Map.put(ctx, :subscription, subscription)
    end

    @tag req: ["FR-706"]
    test "says so when nothing has been sent", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      assert has_element?(lv, "#deliveries-empty")
    end

    @tag req: ["FR-706"]
    test "shows each attempt, with what went wrong", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Plug.Conn.send_resp(&1, 500, ""))

      args = %{
        "subscription_id" => ctx.subscription.id,
        "event" => "session.closed",
        "delivery_id" => "d-1",
        "payload" => %{"session_id" => 1}
      }

      perform_job(WebhookDelivery, args, attempt: 1)
      perform_job(WebhookDelivery, args, attempt: 2)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      assert has_element?(lv, "#deliveries li:nth-child(1)", "attempt 2")
      assert has_element?(lv, "#deliveries li:nth-child(2)", "attempt 1")
      assert has_element?(lv, "#deliveries", "failed")
      assert has_element?(lv, "#deliveries", "HTTP 500")
    end

    @tag req: ["FR-706"]
    test "and a success looks different from a failure", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Plug.Conn.send_resp(&1, 200, ""))

      perform_job(WebhookDelivery, %{
        "subscription_id" => ctx.subscription.id,
        "event" => "session.closed",
        "delivery_id" => "d-2",
        "payload" => %{}
      })

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

      # `[data-tone]` rather than a class: the tone is what the badge means,
      # and it survives the next time the styling changes.
      assert has_element?(
               lv,
               ~s(#deliveries [data-slot="badge"][data-tone="success"]),
               "delivered"
             )
    end
  end
end
