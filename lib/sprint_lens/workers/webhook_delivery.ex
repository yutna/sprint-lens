defmodule SprintLens.Workers.WebhookDelivery do
  @moduledoc """
  Delivers one webhook event, and keeps trying (FR-705, FR-706, §7.4).

  ## The retry curve is the contract

  §7.4 asks for "exponential backoff (for example 1, 5, then 25 minutes) up to
  5 attempts", so that is what `backoff/1` returns — powers of five, in
  minutes. Oban owns the retrying; the HTTP client is told not to retry at
  all, because two layers of backoff would multiply into a curve nobody chose.

  ## Failure is recorded before it is reported

  A failed attempt writes its row and *then* returns `{:error, ...}`. The
  other order would lose the record whenever the process died between the two,
  which is exactly the situation the log exists to explain.

  A subscription that was deleted or switched off between queueing and running
  gets `{:cancel, ...}` rather than an error: there is nothing to retry into,
  and five attempts at a webhook somebody turned off is noise in the log the
  lead reads.
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias SprintLens.Webhooks
  alias SprintLens.Webhooks.Subscription

  # 1, 5, 25, 125 minutes between the five attempts (§7.4).
  @base_minutes 1
  @factor 5

  @timeout_ms 10_000

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(@base_minutes * :math.pow(@factor, attempt - 1) * 60)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    %{
      "subscription_id" => subscription_id,
      "event" => event,
      "delivery_id" => delivery_id,
      "payload" => payload
    } = args

    case Webhooks.get_subscription_by_id(subscription_id) do
      %Subscription{is_active: true} = subscription ->
        deliver(subscription, event, delivery_id, payload, attempt)

      _gone_or_off ->
        {:cancel, :subscription_unavailable}
    end
  end

  defp deliver(subscription, event, delivery_id, payload, attempt) do
    # Encoded once. The signature is over these exact bytes, which is the only
    # way a receiver can check it against what arrived.
    body = Jason.encode!(Webhooks.payload(String.to_existing_atom(event), payload))

    attempt_record = %{
      subscription_id: subscription.id,
      delivery_id: delivery_id,
      event: event,
      attempt: attempt
    }

    :telemetry.span([:sprint_lens, :webhook, :delivery], %{event: event}, fn ->
      result =
        subscription
        |> Webhooks.headers(event, delivery_id, body)
        |> then(&post(subscription.url, body, &1))
        |> record(attempt_record)

      {result, %{event: event, outcome: outcome(result)}}
    end)
  end

  defp post(url, body, headers) do
    Req.new(
      url: url,
      method: :post,
      body: body,
      headers: headers,
      receive_timeout: @timeout_ms,
      # Oban owns the retrying (see the moduledoc).
      retry: false
    )
    |> Req.merge(Application.get_env(:sprint_lens, :webhook_req_options, []))
    |> Req.request()
  end

  # The row is written before the result is returned: the other order loses
  # the record whenever the process dies between the two, which is exactly the
  # situation the log exists to explain (FR-706).
  defp record({:ok, %Req.Response{status: status}}, attempt) when status in 200..299 do
    log(attempt, :delivered, status, nil)

    :ok
  end

  defp record({:ok, %Req.Response{status: status}}, attempt) do
    log(attempt, :failed, status, "HTTP #{status}")

    {:error, {:http_status, status}}
  end

  defp record({:error, reason}, attempt) do
    log(attempt, :failed, nil, Exception.message(reason))

    {:error, reason}
  end

  defp log(attempt, status, code, error) do
    attempt
    |> Map.merge(%{status: Atom.to_string(status), response_code: code, error: error})
    |> Webhooks.record()
  end

  defp outcome(:ok), do: "delivered"
  defp outcome(_error), do: "failed"
end
