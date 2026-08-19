defmodule SprintLens.WebhooksTest do
  @moduledoc """
  Outbound webhooks (FR-704, FR-705, FR-706, §7.4).

  The test this module exists for is `the payload carries nothing anybody
  wrote`. A webhook is the one place a retrospective's contents could leave
  the building without anybody signing in, so the payload is checked by
  encoding it and looking for every card, note and name in the session.
  """

  use SprintLens.DataCase

  alias SprintLens.Actions
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Webhooks
  alias SprintLens.Webhooks.Delivery
  alias SprintLens.Webhooks.Subscription
  alias SprintLens.Workers.ActionDueSweep
  alias SprintLens.Workers.WebhookDelivery

  setup do
    lead = insert(:user, display_name: "Lek")
    team = team_with_lead(lead)
    member = insert(:user, display_name: "Ploy")
    join_team(member, team)

    %{team: team, lead: lead, member: member}
  end

  defp subscribe(ctx, attrs \\ %{}) do
    {:ok, subscription} =
      Webhooks.configure(
        ctx.lead,
        ctx.team,
        Map.merge(
          %{
            url: "https://hooks.example.com/sprintlens",
            secret: "a-secret-long-enough",
            events: ["session.started", "session.closed", "action.due"]
          },
          attrs
        )
      )

    subscription
  end

  describe "configuring a webhook (FR-704)" do
    @tag req: ["FR-704"]
    test "a lead sets a URL, a secret and the events it wants", ctx do
      subscription = subscribe(ctx)

      assert subscription.url == "https://hooks.example.com/sprintlens"
      assert subscription.is_active
      assert Subscription.subscribed(subscription) == Subscription.events()
    end

    @tag req: ["FR-704"]
    test "configuring again replaces it, because a team has one", ctx do
      first = subscribe(ctx)
      second = subscribe(ctx, %{url: "https://elsewhere.example.com/hook"})

      assert first.id == second.id
      assert second.url == "https://elsewhere.example.com/hook"
      assert Repo.aggregate(Subscription, :count) == 1
    end

    @tag req: ["FR-704"]
    test "an address that is not an http URL is refused", ctx do
      for url <- ["not a url", "ftp://files.example.com", "javascript:alert(1)", "/relative"] do
        assert {:error, changeset} =
                 Webhooks.configure(ctx.lead, ctx.team, %{
                   url: url,
                   secret: "a-secret-long-enough",
                   events: ["session.closed"]
                 })

        assert %{url: [_message]} = errors_on(changeset)
      end
    end

    @tag req: ["FR-705"]
    test "a secret that is too short to be one is refused", ctx do
      assert {:error, changeset} =
               Webhooks.configure(ctx.lead, ctx.team, %{
                 url: "https://hooks.example.com/x",
                 secret: "short",
                 events: ["session.closed"]
               })

      assert %{secret: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-705"]
    test "and one can be generated rather than invented", _ctx do
      secret = Subscription.generate_secret()

      assert String.length(secret) >= Subscription.min_secret()
      refute secret == Subscription.generate_secret()
    end

    @tag req: ["FR-704"]
    test "an unknown event name is not subscribed to", ctx do
      subscription = subscribe(ctx, %{events: ["session.closed", "card.created", "nonsense"]})

      assert Subscription.subscribed(subscription) == [:"session.closed"]
    end

    @tag req: ["FR-704"]
    test "a webhook with no events at all is refused", ctx do
      assert {:error, changeset} =
               Webhooks.configure(ctx.lead, ctx.team, %{
                 url: "https://hooks.example.com/x",
                 secret: "a-secret-long-enough",
                 events: []
               })

      assert %{events: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-704"]
    test "only a lead configures it", ctx do
      assert Webhooks.configure(ctx.member, ctx.team, %{url: "https://x.example.com"}) ==
               {:error, :unauthorized}

      assert Webhooks.configure(insert(:user), ctx.team, %{url: "https://x.example.com"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-106", "FR-704"]
    test "and an archived team is read-only here too", ctx do
      {:ok, archived} = SprintLens.Teams.archive_team(ctx.lead, ctx.team)

      assert Webhooks.configure(ctx.lead, archived, %{url: "https://x.example.com"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-704"]
    test "a lead can take it away again", ctx do
      subscribe(ctx)

      assert Webhooks.delete_subscription(ctx.lead, ctx.team) == :ok
      assert Webhooks.get_subscription(ctx.team) == nil
      assert Webhooks.delete_subscription(ctx.lead, ctx.team) == {:error, :not_found}
    end

    @tag req: ["FR-704"]
    test "but nobody else can", ctx do
      subscribe(ctx)

      assert Webhooks.delete_subscription(ctx.member, ctx.team) == {:error, :unauthorized}
      assert Webhooks.get_subscription(ctx.team)
    end

    @tag req: ["FR-704"]
    test "a changeset is available for the form", ctx do
      assert %Ecto.Changeset{} = Webhooks.change_subscription()
      assert %Ecto.Changeset{} = Webhooks.change_subscription(subscribe(ctx), %{})
    end
  end

  describe "the small surfaces around a subscription" do
    @tag req: ["FR-706"]
    test "a delivery has two outcomes and reads its own status", _ctx do
      assert Delivery.statuses() == [:delivered, :failed]
      assert Delivery.status(%Delivery{status: "delivered"}) == :delivered
      assert Delivery.status("failed") == :failed
      assert Delivery.status("exploded") == nil
      assert Delivery.status(nil) == nil
    end

    @tag req: ["FR-704"]
    test "events can be given as a comma-separated string", ctx do
      subscription = subscribe(ctx, %{events: "session.started,action.due"})

      assert Subscription.subscribed(subscription) == [:"session.started", :"action.due"]
    end

    @tag req: ["FR-704"]
    test "and dispatch takes a team as readily as a team id", ctx do
      subscribe(ctx)

      assert Webhooks.dispatch(ctx.team, :"session.started", %{session_id: 1}) == :ok
      assert length(all_jobs()) == 1
    end

    @tag req: ["FR-704"]
    test "a session that would not start announces nothing", ctx do
      subscribe(ctx)
      session = active_session(ctx.team, ctx.lead)

      # Already active: the transition is refused, so there is nothing to say.
      assert Retro.start_session(ctx.lead, session) == {:error, :wrong_state}
      assert all_jobs() == []
    end
  end

  describe "queueing a delivery (FR-704)" do
    @tag req: ["FR-704"]
    test "starting a session announces it", ctx do
      subscribe(ctx)
      session = insert(:session, team: ctx.team, facilitator: ctx.lead)

      {:ok, _started} = Retro.start_session(ctx.lead, session)

      assert [job] = all_jobs()
      assert job.args["event"] == "session.started"
      assert job.args["payload"]["session_id"] == session.id
    end

    @tag req: ["FR-704"]
    test "closing one announces that too, with what it came to", ctx do
      subscribe(ctx)
      session = active_session(ctx.team, ctx.lead)
      {:ok, brainstorming} = Retro.set_phase(ctx.lead, session, :brainstorm)

      {:ok, _card} =
        Board.create_card(ctx.member, brainstorming, %{
          column_id: hd(session.columns).id,
          text: "Deploys are slow"
        })

      {:ok, _closed} = Retro.close_session(ctx.lead, brainstorming)

      assert [closed] = Enum.filter(all_jobs(), &(&1.args["event"] == "session.closed"))
      assert closed.args["payload"]["card_count"] == 1
      assert closed.args["payload"]["participant_count"] == 1
      assert closed.args["payload"]["closed_at"]
    end

    @tag req: ["FR-704"]
    test "a team with no webhook queues nothing, and does not care", ctx do
      session = insert(:session, team: ctx.team, facilitator: ctx.lead)

      assert {:ok, _started} = Retro.start_session(ctx.lead, session)
      assert all_jobs() == []
    end

    @tag req: ["FR-704"]
    test "an event the team did not subscribe to is not queued", ctx do
      subscribe(ctx, %{events: ["action.due"]})
      session = insert(:session, team: ctx.team, facilitator: ctx.lead)

      {:ok, _started} = Retro.start_session(ctx.lead, session)

      assert all_jobs() == []
    end

    @tag req: ["FR-704"]
    test "and a switched-off webhook is not queued to either", ctx do
      subscribe(ctx, %{is_active: false})
      session = insert(:session, team: ctx.team, facilitator: ctx.lead)

      {:ok, _started} = Retro.start_session(ctx.lead, session)

      assert all_jobs() == []
    end
  end

  describe "what a payload may carry (§7.4)" do
    @tag req: ["FR-704"]
    test "ids, counts and the session's own title — and nothing anybody wrote", ctx do
      subscribe(ctx)
      session = active_session(ctx.team, ctx.lead, %{title: "Sprint 12"})
      {:ok, brainstorming} = Retro.set_phase(ctx.lead, session, :brainstorm)

      {:ok, card} =
        Board.create_card(ctx.member, brainstorming, %{
          column_id: hd(session.columns).id,
          text: "Deploys are painfully slow"
        })

      {:ok, discussing} = Retro.set_phase(ctx.lead, brainstorming, :discuss)
      {:ok, _note} = Board.write_note(ctx.lead, discussing, {:card, card.id}, "Fix the build")

      {:ok, _action} =
        Actions.create_action(ctx.member, discussing, %{title: "Write the runbook"})

      {:ok, _closed} = Retro.close_session(ctx.lead, discussing)

      encoded = all_jobs() |> Enum.map(& &1.args) |> Jason.encode!()

      assert encoded =~ "Sprint 12"
      refute encoded =~ "Deploys are painfully slow"
      refute encoded =~ "Fix the build"
      refute encoded =~ "Ploy"
      refute encoded =~ "Lek"
    end

    @tag req: ["FR-704"]
    test "an action's title is the summary, because a reminder needs one", ctx do
      subscribe(ctx)
      session = active_session(ctx.team, ctx.lead)
      {:ok, discussing} = Retro.set_phase(ctx.lead, session, :discuss)

      {:ok, action} =
        Actions.create_action(ctx.member, discussing, %{
          title: "Write the runbook",
          assignee_id: ctx.member.id,
          due_date: DateTime.add(DateTime.utc_now(:second), -1, :day)
        })

      :ok = perform_job(ActionDueSweep, %{})

      assert [job] = Enum.filter(all_jobs(), &(&1.args["event"] == "action.due"))
      assert job.args["payload"]["action_id"] == action.id
      assert job.args["payload"]["title"] == "Write the runbook"
      assert job.args["payload"]["assignee_id"] == ctx.member.id
    end
  end

  describe "announcing an action that has come due (FR-704)" do
    setup ctx do
      subscribe(ctx)
      session = active_session(ctx.team, ctx.lead)
      {:ok, discussing} = Retro.set_phase(ctx.lead, session, :discuss)

      Map.merge(ctx, %{session: discussing})
    end

    defp overdue(ctx, attrs \\ %{}) do
      {:ok, action} =
        Actions.create_action(
          ctx.member,
          ctx.session,
          Map.merge(
            %{
              title: "Write the runbook",
              due_date: DateTime.add(DateTime.utc_now(:second), -1, :day)
            },
            attrs
          )
        )

      action
    end

    @tag req: ["FR-704"]
    test "each one is announced once, however often the sweep runs", ctx do
      overdue(ctx)

      :ok = perform_job(ActionDueSweep, %{})
      assert length(due_jobs()) == 1

      :ok = perform_job(ActionDueSweep, %{})
      assert length(due_jobs()) == 1
    end

    @tag req: ["FR-704"]
    test "an item that is not due yet waits", ctx do
      overdue(ctx, %{due_date: DateTime.add(DateTime.utc_now(:second), 3, :day)})

      :ok = perform_job(ActionDueSweep, %{})

      assert due_jobs() == []
    end

    @tag req: ["FR-704"]
    test "one with no due date is never due", ctx do
      overdue(ctx, %{due_date: nil})

      :ok = perform_job(ActionDueSweep, %{})

      assert due_jobs() == []
    end

    @tag req: ["FR-704"]
    test "and one that is already finished is not chased", ctx do
      action = overdue(ctx)
      {:ok, _done} = Actions.update_action(ctx.member, action, %{status: "done"})

      :ok = perform_job(ActionDueSweep, %{})

      assert due_jobs() == []
    end

    @tag req: ["FR-704"]
    test "the sweep can be told what time it is", ctx do
      overdue(ctx, %{due_date: DateTime.add(DateTime.utc_now(:second), 3, :day)})

      later = DateTime.utc_now() |> DateTime.add(5, :day) |> DateTime.to_iso8601()
      :ok = perform_job(ActionDueSweep, %{"now" => later})

      assert length(due_jobs()) == 1
    end
  end

  describe "signing (FR-705, §7.4)" do
    @tag req: ["FR-705"]
    test "the signature is an HMAC-SHA256 of the body, in hex", _ctx do
      signature = Webhooks.sign("a-secret-long-enough", ~s({"a":1}))

      expected =
        :hmac
        |> :crypto.mac(:sha256, "a-secret-long-enough", ~s({"a":1}))
        |> Base.encode16(case: :lower)

      assert signature == "sha256=" <> expected
    end

    @tag req: ["FR-705"]
    test "and a different body signs differently", _ctx do
      secret = "a-secret-long-enough"

      refute Webhooks.sign(secret, ~s({"a":1})) == Webhooks.sign(secret, ~s({"a":2}))

      refute Webhooks.sign(secret, ~s({"a":1})) ==
               Webhooks.sign("another-long-secret", ~s({"a":1}))
    end

    @tag req: ["FR-705"]
    test "the headers name the event, the delivery and the signature", ctx do
      subscription = subscribe(ctx)
      names = Webhooks.header_names()

      headers = Webhooks.headers(subscription, :"session.closed", "abc-123", "{}")
      lookup = Map.new(headers)

      assert lookup["content-type"] == "application/json"
      assert lookup[names.event] == "session.closed"
      assert lookup[names.delivery] == "abc-123"
      assert lookup[names.signature] == Webhooks.sign(subscription.secret, "{}")
    end
  end

  describe "delivering (FR-706, §7.4)" do
    setup ctx, do: Map.put(ctx, :subscription, subscribe(ctx))

    defp job_args(subscription, overrides \\ %{}) do
      Map.merge(
        %{
          "subscription_id" => subscription.id,
          "event" => "session.closed",
          "delivery_id" => "delivery-1",
          "payload" => %{"session_id" => 1, "title" => "Sprint 12"}
        },
        overrides
      )
    end

    @tag req: ["FR-705", "FR-706"]
    test "a receiver can verify the signature against what arrived", ctx do
      parent = self()

      Req.Test.stub(SprintLens.Webhooks, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:delivered, body, Map.new(conn.req_headers)})

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      assert :ok = perform_job(WebhookDelivery, job_args(ctx.subscription))

      assert_receive {:delivered, body, headers}

      names = Webhooks.header_names()

      # Exactly what a receiver would do: hash the bytes that arrived with the
      # shared secret and compare.
      assert headers[names.signature] == Webhooks.sign(ctx.subscription.secret, body)
      assert headers[names.event] == "session.closed"
      assert headers[names.delivery] == "delivery-1"

      assert %{"event" => "session.closed", "data" => %{"title" => "Sprint 12"}} =
               Jason.decode!(body)
    end

    @tag req: ["FR-706"]
    test "a success is recorded in the log", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Plug.Conn.send_resp(&1, 204, ""))

      assert :ok = perform_job(WebhookDelivery, job_args(ctx.subscription))

      assert [delivery] = Webhooks.list_deliveries(ctx.subscription)
      assert Delivery.status(delivery) == :delivered
      assert delivery.response_code == 204
      assert delivery.attempt == 1
      assert delivery.event == "session.closed"
    end

    @tag req: ["FR-706"]
    test "a refusal is recorded and then reported, so Oban retries", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Plug.Conn.send_resp(&1, 500, "nope"))

      assert {:error, {:http_status, 500}} =
               perform_job(WebhookDelivery, job_args(ctx.subscription))

      assert [delivery] = Webhooks.list_deliveries(ctx.subscription)
      assert Delivery.status(delivery) == :failed
      assert delivery.response_code == 500
      assert delivery.error =~ "500"
    end

    @tag req: ["FR-706"]
    test "so is a connection that never answered", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Req.Test.transport_error(&1, :timeout))

      assert {:error, _reason} = perform_job(WebhookDelivery, job_args(ctx.subscription))

      assert [delivery] = Webhooks.list_deliveries(ctx.subscription)
      assert Delivery.status(delivery) == :failed
      assert delivery.response_code == nil
      assert delivery.error
    end

    @tag req: ["FR-706"]
    test "every attempt gets its own row, so the retries are visible", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Plug.Conn.send_resp(&1, 503, ""))

      for attempt <- 1..3 do
        perform_job(WebhookDelivery, job_args(ctx.subscription), attempt: attempt)
      end

      assert ctx.subscription |> Webhooks.list_deliveries() |> Enum.map(& &1.attempt) == [3, 2, 1]
    end

    @tag req: ["FR-706"]
    test "a webhook somebody removed is cancelled rather than retried", ctx do
      args = job_args(ctx.subscription)
      :ok = Webhooks.delete_subscription(ctx.lead, ctx.team)

      assert {:cancel, :subscription_unavailable} = perform_job(WebhookDelivery, args)
    end

    @tag req: ["FR-706"]
    test "and so is one somebody switched off", ctx do
      subscribe(ctx, %{is_active: false})

      assert {:cancel, :subscription_unavailable} =
               perform_job(WebhookDelivery, job_args(ctx.subscription))
    end

    @tag req: ["FR-706"]
    test "the backoff is one, five, then twenty-five minutes", _ctx do
      minutes =
        for attempt <- 1..4, do: div(WebhookDelivery.backoff(%Oban.Job{attempt: attempt}), 60)

      assert minutes == [1, 5, 25, 125]
    end

    @tag req: ["FR-706"]
    test "the log a lead reads is newest first and bounded", ctx do
      Req.Test.stub(SprintLens.Webhooks, &Plug.Conn.send_resp(&1, 200, ""))

      for attempt <- 1..5 do
        perform_job(WebhookDelivery, job_args(ctx.subscription), attempt: attempt)
      end

      assert ctx.subscription |> Webhooks.list_deliveries(2) |> length() == 2
    end
  end

  defp all_jobs, do: Repo.all(Oban.Job)

  defp due_jobs, do: Enum.filter(all_jobs(), &(&1.args["event"] == "action.due"))
end
