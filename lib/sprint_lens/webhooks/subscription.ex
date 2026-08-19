defmodule SprintLens.Webhooks.Subscription do
  @moduledoc """
  A team's outbound webhook (section 6.3, WEBHOOK_SUBSCRIPTION).

  ## The secret is write-only

  It is cast and stored, and `redact: true` keeps it out of `inspect/1` and
  out of any log line that prints a struct. The form never renders it back
  either: a shared secret that appears on every page render is a secret with
  a much larger surface than it needs.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Changesets
  alias SprintLens.Teams.Team

  @type t :: %__MODULE__{}
  @type event :: :"session.started" | :"session.closed" | :"action.due"

  # FR-704, verbatim. These are the three a chat integration can act on: a
  # retro is starting, a retro produced something, a commitment is due.
  @events [:"session.started", :"session.closed", :"action.due"]
  @event_names Enum.map(@events, &Atom.to_string/1)

  @min_secret 16

  schema "webhook_subscriptions" do
    field :url, :string
    field :secret, :string, redact: true
    field :events, :string
    field :is_active, :boolean, default: true

    belongs_to :team, Team

    timestamps(type: :utc_datetime)
  end

  @doc """
  The three events a webhook can subscribe to (FR-704).
  """
  @spec events() :: [event()]
  def events, do: @events

  @doc """
  The shortest secret that will be accepted.
  """
  @spec min_secret() :: pos_integer()
  def min_secret, do: @min_secret

  @doc """
  Generates a secret, for the common case where nobody has one in mind.
  """
  @spec generate_secret() :: String.t()
  def generate_secret, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  The events this subscription wants, as atoms.
  """
  @spec subscribed(t()) :: [event()]
  def subscribed(%__MODULE__{events: events}) do
    events
    |> String.split(",", trim: true)
    |> Enum.filter(&(&1 in @event_names))
    |> Enum.map(&String.to_existing_atom/1)
  end

  @doc """
  Whether this subscription wants to hear about `event`.
  """
  @spec wants?(t(), event()) :: boolean()
  def wants?(%__MODULE__{is_active: false}, _event), do: false
  def wants?(%__MODULE__{} = subscription, event), do: event in subscribed(subscription)

  @doc """
  A changeset for creating or editing a subscription (FR-704).
  """
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:team_id, :url, :secret, :is_active])
    |> put_events(attrs)
    |> Changesets.trim(:url)
    |> validate_required([:team_id, :url, :secret, :events])
    |> validate_url()
    |> validate_length(:secret, min: @min_secret)
    |> unique_constraint(:team_id)
    |> foreign_key_constraint(:team_id)
  end

  # Stored as a comma-separated string rather than as JSON: it is a short
  # closed set, and a `LIKE`-free exact membership test is easier to read
  # than a JSON extraction in SQLite.
  defp put_events(changeset, attrs) do
    case attrs["events"] || attrs[:events] do
      nil ->
        changeset

      list when is_list(list) ->
        selected = list |> Enum.map(&to_string/1) |> Enum.filter(&(&1 in @event_names))

        put_change(changeset, :events, Enum.join(selected, ","))

      string when is_binary(string) ->
        put_events(changeset, %{"events" => String.split(string, ",", trim: true)})
    end
  end

  # A webhook posts wherever it is told to, so where it is told to matters.
  # `http` is allowed because a self-hosted receiver on a private network is
  # a normal deployment; anything that is not an absolute HTTP URL is not.
  defp validate_url(changeset) do
    case get_field(changeset, :url) do
      nil ->
        changeset

      url ->
        case URI.new(url) do
          {:ok, %URI{scheme: scheme, host: host}}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            changeset

          _other ->
            add_error(changeset, :url, "must be an http or https address")
        end
    end
  end
end
