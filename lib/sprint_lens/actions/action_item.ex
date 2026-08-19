defmodule SprintLens.Actions.ActionItem do
  @moduledoc """
  One follow-up the team owns (section 6.3, ACTION_ITEM).

  ## It belongs to the team, not to the session

  A session produces action items; it does not contain them. FR-503 lets
  anyone in the team update one "at any time, including after the session
  closes", and section 6.4 keeps them alive when the session they came from is
  deleted. So the team is the required reference and everything about the
  session — which one, which topic — is optional context.

  ## Carrying over

  FR-505 lets an item still open at the next check-in be carried into that
  session as a *new* item that links back with `carried_from`. The original is
  left exactly as it was: rewriting its status to say "carried" would either
  invent a status section 6.3 does not have, or lie to the completion counts
  FR-506 feeds. Instead the original stops appearing in the open list because
  something newer stands in for it — see `SprintLens.Actions.open_query/1`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Changesets
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic
  alias SprintLens.Teams.Team

  @type t :: %__MODULE__{}
  @type status :: :open | :in_progress | :done | :dropped

  # Section 6.3, in the order a piece of work moves through them.
  @statuses [:open, :in_progress, :done, :dropped]
  @status_names Enum.map(@statuses, &Atom.to_string/1)

  # The statuses that still ask something of the team. `dropped` is a decision
  # not to act, which is finished in the same way `done` is.
  @live_statuses [:open, :in_progress]

  @max_title 200
  @max_description 4_000

  schema "action_items" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "open"
    field :due_date, :utc_datetime
    field :client_request_id, :string

    belongs_to :team, Team
    belongs_to :session, Session
    belongs_to :card, Card
    belongs_to :card_group, CardGroup
    belongs_to :assignee, User
    belongs_to :carried_from, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc """
  The four statuses of section 6.3.
  """
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  The statuses that still ask something of the team (FR-505, FR-506).
  """
  @spec live_statuses() :: [status()]
  def live_statuses, do: @live_statuses

  @doc """
  The status as an atom.
  """
  @spec status(t() | String.t() | nil) :: status() | nil
  def status(%__MODULE__{status: status}), do: status(status)
  def status(status) when status in @status_names, do: String.to_existing_atom(status)
  def status(status) when status in @statuses, do: status
  def status(_other), do: nil

  @doc """
  Whether this item is still asking something of the team.
  """
  @spec live?(t()) :: boolean()
  def live?(%__MODULE__{} = item), do: status(item) in @live_statuses

  @doc """
  The longest a title may be.
  """
  @spec max_title() :: pos_integer()
  def max_title, do: @max_title

  @doc """
  A changeset for creating an item (FR-501, FR-502).
  """
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :team_id,
      :session_id,
      :card_id,
      :card_group_id,
      :assignee_id,
      :carried_from_id,
      :title,
      :description,
      :status,
      :due_date,
      :client_request_id
    ])
    |> validate_required([:team_id])
    |> shared_validations()
    |> unique_constraint([:team_id, :client_request_id])
    |> unique_constraint(:carried_from_id)
  end

  @doc """
  A changeset for editing an item (FR-503).

  Which team it belongs to and which session produced it are not editable: an
  action item's origin is history, and moving one between teams would take its
  session link somewhere it does not belong.
  """
  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :description, :status, :due_date, :assignee_id])
    |> shared_validations()
  end

  defp shared_validations(changeset) do
    changeset
    |> Changesets.trim(:title)
    |> validate_required([:title, :status])
    |> validate_length(:title, min: 1, max: @max_title)
    |> validate_length(:description, max: @max_description)
    |> validate_inclusion(:status, @status_names)
    |> validate_one_topic()
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:assignee_id)
  end

  # An action may be linked to a topic or to nothing at all (FR-501, "optionally
  # linked to the focused topic"); it may not be linked to two.
  defp validate_one_topic(changeset) do
    card_id = get_field(changeset, :card_id)
    group_id = get_field(changeset, :card_group_id)

    if is_nil(card_id) and is_nil(group_id) do
      changeset
    else
      case Topic.from_ids(card_id, group_id) do
        {:ok, _ref} -> changeset
        :error -> add_error(changeset, :card_id, "must name at most one card or group")
      end
    end
  end
end
