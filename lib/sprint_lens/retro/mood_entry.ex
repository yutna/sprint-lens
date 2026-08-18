defmodule SprintLens.Retro.MoodEntry do
  @moduledoc """
  One check-in mood or wrap-up ROTI answer (section 6.3, MOOD_ENTRY).

  Both are a score from one to five about how a person feels, asked at
  different moments: the mood at check-in (FR-211) and the return on time
  invested at wrap-up (FR-214). They share a table because they share a shape
  and both feed the same insights (FR-604).

  Participants only ever see aggregates (FR-211). The individual answers exist
  so a person can change their own, and so the aggregate can be computed —
  not so anyone can look up how a colleague felt.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Retro.Session

  @type t :: %__MODULE__{}
  @type kind :: :checkin_mood | :roti

  @kinds [:checkin_mood, :roti]
  @kind_names Enum.map(@kinds, &Atom.to_string/1)

  @min_score 1
  @max_score 5

  schema "mood_entries" do
    field :kind, :string
    field :score, :integer
    field :word, :string

    belongs_to :session, Session
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  The two kinds of answer collected (FR-211, FR-214).
  """
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  The permitted score range: one to five (FR-211, FR-214).
  """
  @spec score_bounds() :: {pos_integer(), pos_integer()}
  def score_bounds, do: {@min_score, @max_score}

  @doc """
  A changeset for recording or changing an answer.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:session_id, :user_id, :kind, :score, :word])
    |> validate_required([:session_id, :kind, :score])
    |> validate_inclusion(:kind, @kind_names)
    |> validate_number(:score,
      greater_than_or_equal_to: @min_score,
      less_than_or_equal_to: @max_score
    )
    |> trim_word()
    # FR-211 asks for "an optional one-word note", so the field is short by
    # design rather than a free-text box in disguise.
    |> validate_length(:word, max: 40)
    |> unique_constraint([:session_id, :user_id, :kind],
      name: :mood_entries_one_per_person,
      message: "has already been answered"
    )
  end

  @doc """
  The kind as an atom.
  """
  @spec kind(t() | String.t() | nil) :: kind() | nil
  def kind(%__MODULE__{kind: kind}), do: kind(kind)
  def kind(kind) when kind in @kind_names, do: String.to_existing_atom(kind)
  def kind(kind) when kind in @kinds, do: kind
  def kind(_other), do: nil

  defp trim_word(changeset) do
    update_change(changeset, :word, fn
      nil -> nil
      word -> word |> String.trim() |> String.split(~r/\s+/) |> List.first()
    end)
  end
end
