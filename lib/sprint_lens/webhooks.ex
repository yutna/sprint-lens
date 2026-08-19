defmodule SprintLens.Webhooks do
  @moduledoc """
  Telling somebody else's system that something happened here (FR-704 to
  FR-706, §7.4).

  ## The payload rule, and why it is enforced here

  §7.4: "Payloads carry ids and summary fields, never card text, so a chat
  message can link back into the app without leaking content." A retrospective
  is the most sensitive thing this app holds, and a webhook is the one place
  its contents could leave the building without anybody signing in. So the
  payloads are built by `payload/2` from ids, counts and titles — never from a
  card, a note or a name — and a test reads the encoded body back looking for
  each of those.

  An action item's *title* is in the payload, and that is a decision rather
  than an oversight: `action.due` exists so a chat message can say which
  commitment is due, and "action 41 is due" is a notification nobody can act
  on. The title is the summary §7.4 asks for.

  ## Signing

  The signature is computed over the exact bytes that are sent. The body is
  encoded once, signed, and handed to the HTTP client as a string — signing a
  map and encoding it again later would work until the day the key order
  changed.
  """

  import Ecto.Query, warn: false

  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLens.Teams.Team
  alias SprintLens.Webhooks.Delivery
  alias SprintLens.Webhooks.Subscription
  alias SprintLens.Workers.WebhookDelivery

  @header_event "x-sprintlens-event"
  @header_delivery "x-sprintlens-delivery"
  @header_signature "x-sprintlens-signature"

  ## Reading

  @doc """
  A team's webhook, or `nil` (FR-704).
  """
  @spec get_subscription(Team.t()) :: Subscription.t() | nil
  def get_subscription(%Team{} = team), do: Repo.get_by(Subscription, team_id: team.id)

  @doc """
  The delivery log a Team Lead reads (FR-706), newest first.

  Capped rather than complete: a lead is asking "is it working?", which the
  last few dozen attempts answer, and an unbounded query on a page nobody
  paginates is a slow way to make the app feel broken.
  """
  @spec list_deliveries(Subscription.t(), pos_integer()) :: [Delivery.t()]
  def list_deliveries(%Subscription{} = subscription, limit \\ 50) do
    Repo.all(
      from d in Delivery,
        where: d.subscription_id == ^subscription.id,
        order_by: [desc: d.inserted_at, desc: d.id],
        limit: ^limit
    )
  end

  @doc """
  A changeset for the webhook form.
  """
  def change_subscription(%Subscription{} = subscription \\ %Subscription{}, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  ## Writing

  @doc """
  Configures a team's webhook, replacing whatever was there (FR-704).

  Only a Team Lead or an Org Admin, per section 3.1's `manage_webhooks`.
  """
  @spec configure(User.t() | Scope.t(), Team.t(), map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def configure(actor, %Team{} = team, attrs) do
    with :ok <- authorize(actor, team) do
      attrs = attrs |> stringify() |> Map.put("team_id", team.id)

      (get_subscription(team) || %Subscription{})
      |> Subscription.changeset(attrs)
      |> Repo.insert_or_update()
    end
  end

  @doc """
  Removes a team's webhook, and the log of what it delivered (FR-704).
  """
  @spec delete_subscription(User.t() | Scope.t(), Team.t()) :: :ok | {:error, atom()}
  def delete_subscription(actor, %Team{} = team) do
    with :ok <- authorize(actor, team) do
      case get_subscription(team) do
        nil -> {:error, :not_found}
        subscription -> Repo.delete!(subscription) && :ok
      end
    end
  end

  ## Dispatch

  @doc """
  Queues a delivery of `event` for the team, if it wants that event
  (FR-704).

  Returns `:ok` whether or not anything was queued: a team with no webhook is
  the normal case, and the session that triggered this must not care.
  """
  @spec dispatch(Team.t() | term(), Subscription.event(), map()) :: :ok
  def dispatch(%Team{} = team, event, payload), do: dispatch(team.id, event, payload)

  def dispatch(team_id, event, payload) do
    case Repo.get_by(Subscription, team_id: team_id) do
      %Subscription{} = subscription ->
        if Subscription.wants?(subscription, event), do: enqueue(subscription, event, payload)

        :ok

      nil ->
        :ok
    end
  end

  defp enqueue(subscription, event, payload) do
    %{
      subscription_id: subscription.id,
      event: Atom.to_string(event),
      delivery_id: Ecto.UUID.generate(),
      payload: payload
    }
    |> WebhookDelivery.new()
    |> Oban.insert()
  end

  @doc """
  Announces that a session has started (FR-704).
  """
  @spec session_started(Session.t()) :: :ok
  def session_started(%Session{} = session) do
    dispatch(session.team_id, :"session.started", session_payload(session))
  end

  @doc """
  Announces that a session has closed, with what it came to (FR-704).
  """
  @spec session_closed(Session.t()) :: :ok
  def session_closed(%Session{} = session) do
    dispatch(session.team_id, :"session.closed", session_payload(session))
  end

  @doc """
  Announces that an action item has reached its due date (FR-704).
  """
  @spec action_due(ActionItem.t()) :: :ok
  def action_due(%ActionItem{} = action) do
    dispatch(action.team_id, :"action.due", action_payload(action))
  end

  ## Payloads (§7.4)

  @doc """
  The body sent for an event: ids, counts and titles, and nothing anybody
  wrote on a card (§7.4).
  """
  @spec payload(Subscription.event(), map()) :: map()
  def payload(event, data) do
    %{
      event: Atom.to_string(event),
      occurred_at: DateTime.utc_now(),
      data: data
    }
  end

  defp session_payload(%Session{} = session) do
    %{
      session_id: session.id,
      team_id: session.team_id,
      # The session's own title, which is what a chat message needs to be
      # worth reading. Not a card, not a note, not a name.
      title: session.title,
      state: session.state,
      phase: session.phase,
      is_anonymous: session.is_anonymous,
      card_count: Board.count_cards(session),
      participant_count: session.participant_count,
      closed_at: session.closed_at
    }
  end

  defp action_payload(%ActionItem{} = action) do
    %{
      action_id: action.id,
      team_id: action.team_id,
      session_id: action.session_id,
      title: action.title,
      status: action.status,
      due_date: action.due_date,
      assignee_id: action.assignee_id
    }
  end

  ## Signing (FR-705, §7.4)

  @doc """
  The headers a delivery carries (§7.4).

  The signature is `sha256=` followed by the hex HMAC of exactly the bytes in
  `body`, so a receiver can verify it by hashing what arrived.
  """
  @spec headers(Subscription.t(), Subscription.event() | String.t(), String.t(), String.t()) ::
          [{String.t(), String.t()}]
  def headers(%Subscription{} = subscription, event, delivery_id, body) do
    [
      {"content-type", "application/json"},
      {@header_event, to_string(event)},
      {@header_delivery, delivery_id},
      {@header_signature, sign(subscription.secret, body)}
    ]
  end

  @doc """
  The HMAC-SHA256 signature of `body` under `secret` (FR-705).
  """
  @spec sign(String.t(), String.t()) :: String.t()
  def sign(secret, body) do
    "sha256=" <> (:hmac |> :crypto.mac(:sha256, secret, body) |> Base.encode16(case: :lower))
  end

  @doc """
  The header names a delivery uses, so tests and documentation agree with the
  code.
  """
  @spec header_names() :: %{event: String.t(), delivery: String.t(), signature: String.t()}
  def header_names do
    %{event: @header_event, delivery: @header_delivery, signature: @header_signature}
  end

  ## Recording (FR-706)

  @doc """
  Records one attempt at a delivery, whether it worked or not.
  """
  @spec record(map()) :: {:ok, Delivery.t()} | {:error, Ecto.Changeset.t()}
  def record(attrs) do
    %Delivery{}
    |> Delivery.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  A subscription by id, or `nil` — used by the worker, which holds an id
  rather than a struct because a job outlives the process that queued it.
  """
  @spec get_subscription_by_id(term()) :: Subscription.t() | nil
  def get_subscription_by_id(id), do: Repo.fetch(Subscription, id)

  defp authorize(actor, %Team{} = team) do
    if Policy.manage?(actor, :manage_webhooks, Teams.role(actor, team), team.is_archived) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
end
