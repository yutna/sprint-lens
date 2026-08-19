defmodule SprintLens.Webhooks.Delivery do
  @moduledoc """
  One attempt at delivering one event (FR-706).

  A row per *attempt*, not per event: the retries are what the Team Lead
  needs to see, and a row that got overwritten each time would show only the
  last one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Webhooks.Subscription

  @type t :: %__MODULE__{}
  @type status :: :delivered | :failed

  @statuses [:delivered, :failed]
  @status_names Enum.map(@statuses, &Atom.to_string/1)

  schema "webhook_deliveries" do
    field :delivery_id, :string
    field :event, :string
    field :attempt, :integer, default: 1
    field :status, :string
    field :response_code, :integer
    field :error, :string

    belongs_to :subscription, Subscription

    timestamps(type: :utc_datetime)
  end

  @doc """
  The two outcomes an attempt can have.
  """
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  The status as an atom.
  """
  @spec status(t() | String.t() | nil) :: status() | nil
  def status(%__MODULE__{status: status}), do: status(status)
  def status(status) when status in @status_names, do: String.to_existing_atom(status)
  def status(_other), do: nil

  @doc """
  A changeset for recording an attempt.
  """
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :subscription_id,
      :delivery_id,
      :event,
      :attempt,
      :status,
      :response_code,
      :error
    ])
    |> validate_required([:subscription_id, :delivery_id, :event, :attempt, :status])
    |> validate_inclusion(:status, @status_names)
    # The error is for a person to read, not a place to keep a stack trace.
    |> update_change(:error, &String.slice(&1, 0, 500))
    |> foreign_key_constraint(:subscription_id)
  end
end
