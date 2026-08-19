defmodule SprintLens.Retro.Card do
  @moduledoc """
  One reflection written by a participant (section 6.3, CARD).

  ## Why `author_id` is nullable

  Two different reasons, and both matter:

    * an anonymous session strips authorship irreversibly when it closes
      (FR-210, NFR-304) — the reference is deleted, not hidden;
    * a PDPA erasure nullifies a person's references while leaving the
      de-identified content behind (FR-805, section 6.4).

  So code reading a card must never assume it has an author.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Changesets
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.Session

  @type t :: %__MODULE__{}

  # FR-301: card text is limited to 500 characters, with a live counter.
  @max_text 500

  schema "cards" do
    field :text, :string
    field :position, :integer
    field :client_request_id, :string

    belongs_to :column, Column
    belongs_to :author, User
    belongs_to :card_group, CardGroup

    timestamps(type: :utc_datetime)
  end

  @doc """
  The character limit a card's text is held to (FR-301).
  """
  @spec max_text() :: pos_integer()
  def max_text, do: @max_text

  @doc """
  A changeset for writing a new card.
  """
  def create_changeset(card, attrs) do
    card
    |> cast(attrs, [:column_id, :author_id, :text, :position, :client_request_id])
    |> validate_required([:column_id, :text, :position])
    |> validate_text()
    |> unique_constraint([:column_id, :client_request_id])
  end

  @doc """
  A changeset for editing the text of an existing card (FR-301).
  """
  def update_changeset(card, attrs) do
    card
    |> cast(attrs, [:text])
    |> validate_required([:text])
    |> validate_text()
  end

  @doc """
  A changeset for moving a card between columns or within one (FR-303,
  FR-305).
  """
  def move_changeset(card, attrs) do
    card
    |> cast(attrs, [:column_id, :position])
    |> validate_required([:column_id, :position])
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end

  @doc """
  A changeset for putting a card into a cluster, or taking it out (FR-304).
  """
  def group_changeset(card, card_group_id) do
    change(card, card_group_id: card_group_id)
  end

  @doc """
  Whether `user` may see this card right now.

  In blind mode during brainstorm, a card is visible only to the person who
  wrote it until the facilitator reveals them all (FR-209). This is applied
  where a card is rendered, not where it is broadcast: a broadcast fans out to
  everyone, so the viewer is only known at the edge.
  """
  @spec visible_to?(t(), User.t() | nil, Session.t()) :: boolean()
  def visible_to?(_card, _user, %Session{is_blind: false}), do: true
  def visible_to?(_card, _user, %Session{cards_revealed: true}), do: true
  def visible_to?(%__MODULE__{author_id: nil}, _user, _session), do: false
  def visible_to?(%__MODULE__{author_id: author_id}, %User{id: id}, _session), do: author_id == id
  def visible_to?(_card, _user, _session), do: false

  defp validate_text(changeset) do
    changeset
    |> Changesets.trim(:text)
    |> validate_length(:text, min: 1, max: @max_text)
  end
end
