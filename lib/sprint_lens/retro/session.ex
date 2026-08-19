defmodule SprintLens.Retro.Session do
  @moduledoc """
  One retrospective meeting (section 6.3, RETRO_SESSION).

  ## The two things that cannot change after creation

  `is_anonymous` is fixed at creation and never cast again: FR-210 says the
  mode "cannot be turned off after the session starts", and people write cards
  believing the promise made when they joined.

  `join_code` is fixed for the same reason a meeting link is: it has already
  been shared.

  ## Why the timer is three fields and not a process

  FR-208 wants every participant to see the same countdown. Broadcasting a
  tick every second to fifty people (NFR-103) would be both wasteful and
  wrong — network jitter would make the numbers disagree. Instead the server
  records when the timer started and how long it runs, and each client derives
  the remaining time. A paused timer keeps what was left in
  `timer_remaining_s` and clears `timer_started_at`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Changesets
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.Topic
  alias SprintLens.Teams.Team
  alias SprintLens.Teams.Template

  @type t :: %__MODULE__{}
  @type phase :: :checkin | :brainstorm | :group | :vote | :discuss | :wrapup
  @type state :: :created | :active | :closed

  # The six ordered phases of section 4.3. Declared as atoms so they exist
  # from compile time: deriving them with `String.to_existing_atom/1` would
  # depend on something else having mentioned them first.
  @phases [:checkin, :brainstorm, :group, :vote, :discuss, :wrapup]
  @phase_names Enum.map(@phases, &Atom.to_string/1)

  @states [:created, :active, :closed]
  @state_names Enum.map(@states, &Atom.to_string/1)

  # Unambiguous characters only: a join code is read aloud and typed on a
  # phone, so no O/0 or I/1/L confusion (FR-204).
  @code_alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"
  @code_length 6

  schema "retro_sessions" do
    field :title, :string
    field :scheduled_at, :utc_datetime
    field :state, :string, default: "created"
    field :phase, :string, default: "checkin"

    field :is_anonymous, :boolean, default: false
    field :is_blind, :boolean, default: false
    field :cards_revealed, :boolean, default: false
    field :votes_revealed, :boolean, default: false

    field :vote_budget, :integer, default: 5
    field :multi_vote, :boolean, default: false
    field :join_code, :string

    field :timer_duration_s, :integer
    field :timer_started_at, :utc_datetime_usec
    field :timer_remaining_s, :integer

    field :closed_at, :utc_datetime

    # Taken at close, before an anonymous session's references are destroyed.
    # See the migration for why it is stored rather than counted.
    field :participant_count, :integer

    # The recap summary a facilitator accepted, if they accepted one
    # (AI-009). Copied here rather than read back through the suggestion, so
    # purging the suggestions cannot empty a recap somebody signed off.
    field :summary, :string

    belongs_to :team, Team
    belongs_to :template, Template
    belongs_to :facilitator, User

    # The topic everyone's screen is following (FR-406). Two references with
    # at most one set, the same shape a vote and a note use.
    belongs_to :focus_card, Card
    belongs_to :focus_card_group, CardGroup

    has_many :columns, Column, foreign_key: :session_id, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  The six phases, in order (section 4.3).
  """
  @spec phases() :: [phase()]
  def phases, do: @phases

  @doc """
  The session lifecycle states (FR-205).
  """
  @spec states() :: [state()]
  def states, do: @states

  @doc """
  A changeset for creating a session (FR-201, FR-203).
  """
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :title,
      :scheduled_at,
      :team_id,
      :template_id,
      :facilitator_id,
      :is_anonymous,
      :is_blind,
      :vote_budget,
      :multi_vote
    ])
    |> validate_required([:title, :team_id, :facilitator_id])
    |> Changesets.trim(:title)
    |> validate_length(:title, min: 1, max: 120)
    |> validate_number(:vote_budget, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> put_join_code()
    |> unique_constraint(:join_code)
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:template_id)
  end

  @doc """
  A changeset for moving the session between `created`, `active` and `closed`
  (FR-205).
  """
  def state_changeset(session, state) when state in @state_names do
    session
    |> change(state: state)
    |> put_closed_at(state)
  end

  @doc """
  A changeset for the current phase (FR-206).
  """
  def phase_changeset(session, phase) when phase in @phase_names do
    change(session, phase: phase)
  end

  @doc """
  A changeset for handing the facilitator role to someone else (FR-207).
  """
  def facilitator_changeset(session, user_id) do
    session
    |> change(facilitator_id: user_id)
    |> foreign_key_constraint(:facilitator_id)
  end

  @doc """
  A changeset for the count of people who took part (FR-601, FR-604).
  """
  def participants_changeset(session, count) do
    change(session, participant_count: count)
  end

  @doc """
  A changeset for the accepted AI summary (AI-002, AI-009).
  """
  def summary_changeset(session, summary), do: change(session, summary: summary)

  @doc """
  A changeset for the reveal flags (FR-209, FR-404).
  """
  def reveal_changeset(session, attrs) do
    cast(session, attrs, [:cards_revealed, :votes_revealed])
  end

  @doc """
  A changeset for the focused topic (FR-406).

  Passing `nil` for both clears the spotlight, which is what "no topic" means
  — there is no separate flag for it.
  """
  def focus_changeset(session, card_id, card_group_id) do
    session
    |> change(focus_card_id: card_id, focus_card_group_id: card_group_id)
    |> foreign_key_constraint(:focus_card_id)
    |> foreign_key_constraint(:focus_card_group_id)
  end

  @doc """
  The focused topic as a `SprintLens.Retro.Topic` reference, or `nil`
  (FR-406).
  """
  @spec focus(t()) :: Topic.ref() | nil
  def focus(%__MODULE__{focus_card_id: card_id, focus_card_group_id: group_id}) do
    case Topic.from_ids(card_id, group_id) do
      {:ok, ref} -> ref
      :error -> nil
    end
  end

  @doc """
  A changeset for the timer fields (FR-208).
  """
  def timer_changeset(session, attrs) do
    session
    |> cast(attrs, [:timer_duration_s, :timer_started_at, :timer_remaining_s])
    |> validate_number(:timer_duration_s,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 3_600
    )
  end

  @doc """
  The phase as an atom.
  """
  @spec phase(t() | String.t() | nil) :: phase() | nil
  def phase(%__MODULE__{phase: phase}), do: phase(phase)
  def phase(phase) when phase in @phase_names, do: String.to_existing_atom(phase)
  def phase(phase) when phase in @phases, do: phase
  def phase(_other), do: nil

  @doc """
  The lifecycle state as an atom.
  """
  @spec state(t() | String.t() | nil) :: state() | nil
  def state(%__MODULE__{state: state}), do: state(state)
  def state(state) when state in @state_names, do: String.to_existing_atom(state)
  def state(state) when state in @states, do: state
  def state(_other), do: nil

  @doc """
  The phase after `phase`, or `nil` at the end (FR-206).
  """
  @spec next_phase(phase() | t()) :: phase() | nil
  def next_phase(%__MODULE__{} = session), do: next_phase(phase(session))
  def next_phase(phase), do: step(phase, 1)

  @doc """
  The phase before `phase`, or `nil` at the start (FR-206).
  """
  @spec previous_phase(phase() | t()) :: phase() | nil
  def previous_phase(%__MODULE__{} = session), do: previous_phase(phase(session))
  def previous_phase(phase), do: step(phase, -1)

  @doc """
  Whether `phase` comes after the session's current one — which is what
  "skipping a phase" means (FR-206).
  """
  @spec ahead?(t(), phase()) :: boolean()
  def ahead?(%__MODULE__{} = session, phase) do
    with current when not is_nil(current) <- phase(session),
         target when not is_nil(target) <- index(phase) do
      target > index(current)
    else
      _unknown -> false
    end
  end

  @doc """
  Seconds left on the timer at `now`, or `nil` when no timer is set.

  Derived rather than stored, so every client agrees without the server
  broadcasting a tick (FR-208).
  """
  @spec timer_remaining(t(), DateTime.t()) :: non_neg_integer() | nil
  def timer_remaining(session, now \\ DateTime.utc_now())

  def timer_remaining(%__MODULE__{timer_started_at: nil, timer_remaining_s: remaining}, _now) do
    remaining
  end

  def timer_remaining(%__MODULE__{} = session, now) do
    elapsed = DateTime.diff(now, session.timer_started_at)

    max(session.timer_duration_s - elapsed, 0)
  end

  @doc """
  Whether the timer is currently counting down.
  """
  @spec timer_running?(t()) :: boolean()
  def timer_running?(%__MODULE__{timer_started_at: started_at}), do: not is_nil(started_at)

  @doc """
  Generates a join code (FR-204).
  """
  @spec generate_join_code() :: String.t()
  def generate_join_code do
    1..@code_length
    |> Enum.map(fn _ -> Enum.random(@code_alphabet) end)
    |> List.to_string()
  end

  @doc """
  Normalises a code a person typed: upper case, no spaces or dashes.
  """
  @spec normalise_join_code(String.t() | nil) :: String.t()
  def normalise_join_code(nil), do: ""

  def normalise_join_code(code) do
    code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")
  end

  defp put_join_code(changeset) do
    if get_field(changeset, :join_code) do
      changeset
    else
      put_change(changeset, :join_code, generate_join_code())
    end
  end

  defp put_closed_at(changeset, "closed") do
    put_change(changeset, :closed_at, DateTime.utc_now(:second))
  end

  defp put_closed_at(changeset, _state), do: changeset

  defp step(phase, offset) do
    case index(phase) do
      nil -> nil
      current -> phases() |> Enum.at(current + offset) |> guard(current + offset)
    end
  end

  # `Enum.at/2` wraps for negative indexes, which would turn "before the first
  # phase" into "the last phase".
  defp guard(_phase, index) when index < 0, do: nil
  defp guard(phase, _index), do: phase

  defp index(phase), do: Enum.find_index(phases(), &(&1 == phase))
end
