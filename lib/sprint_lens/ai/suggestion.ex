defmodule SprintLens.AI.Suggestion do
  @moduledoc """
  One AI job and what came back (section 6.3 AI_SUGGESTION, §5.2).

  ## Six types and six statuses, both closed sets

  The types are section 5.4's features and the statuses are section 6.3's
  list. Both are declared as atoms at compile time so a typo is a compile
  error rather than a row nobody can read.

  ## Two outputs

  `output` is what the model said. `accepted_output` is what a human agreed
  to, which AI-002 lets them edit first. Keeping both is what makes it
  possible to ask later whether the suggestions were any good.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Retro.Session
  alias SprintLens.Teams.Team

  @type t :: %__MODULE__{}
  @type type ::
          :session_summary
          | :clustering
          | :action_draft
          | :recurring_themes
          | :icebreakers
          | :translation
  @type status :: :queued | :running | :ready | :failed | :accepted | :rejected

  # Section 5.4, one per feature.
  @types [
    :session_summary,
    :clustering,
    :action_draft,
    :recurring_themes,
    :icebreakers,
    :translation
  ]
  @type_names Enum.map(@types, &Atom.to_string/1)

  @statuses [:queued, :running, :ready, :failed, :accepted, :rejected]
  @status_names Enum.map(@statuses, &Atom.to_string/1)

  # The statuses a human can still act on. A suggestion that has been
  # accepted or rejected is a decision, not a question.
  @open_statuses [:queued, :running, :ready]

  schema "ai_suggestions" do
    field :type, :string
    field :status, :string, default: "queued"
    field :input_scope, :string
    field :output, :string
    field :accepted_output, :string
    field :error, :string
    field :duration_ms, :integer
    field :input_bytes, :integer

    belongs_to :team, Team
    belongs_to :session, Session
    belongs_to :requested_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  The six features of section 5.4.
  """
  @spec types() :: [type()]
  def types, do: @types

  @doc """
  The statuses of section 6.3.
  """
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  Reads a type name from a parameter, or `:error`.
  """
  @spec parse_type(term()) :: {:ok, type()} | :error
  def parse_type(value) when value in @types, do: {:ok, value}

  def parse_type(value) when is_binary(value) do
    if value in @type_names, do: {:ok, String.to_existing_atom(value)}, else: :error
  end

  def parse_type(_value), do: :error

  @doc """
  The type as an atom.
  """
  @spec type(t()) :: type() | nil
  def type(%__MODULE__{type: type}) do
    case parse_type(type) do
      {:ok, parsed} -> parsed
      :error -> nil
    end
  end

  @doc """
  The status as an atom.
  """
  @spec status(t() | String.t() | nil) :: status() | nil
  def status(%__MODULE__{status: status}), do: status(status)
  def status(status) when status in @status_names, do: String.to_existing_atom(status)
  def status(status) when status in @statuses, do: status
  def status(_other), do: nil

  @doc """
  Whether a human still has something to decide about this one.
  """
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{} = suggestion), do: status(suggestion) in @open_statuses

  @doc """
  What was sent, as the list §5.2's envelope shows.
  """
  @spec input_scope(t()) :: [String.t()]
  def input_scope(%__MODULE__{input_scope: scope}), do: String.split(scope || "", ",", trim: true)

  @doc """
  A changeset for asking for a suggestion (AI-005).
  """
  def request_changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [:team_id, :session_id, :requested_by_id, :type, :input_bytes])
    # Set rather than cast: an icebreaker job sends nothing about the team at
    # all, so its scope is the empty string — which `cast/3` reads as "not
    # given" and drops (AI-015).
    |> put_change(:input_scope, attrs[:input_scope] || attrs["input_scope"] || "")
    |> validate_required([:team_id, :type])
    |> validate_inclusion(:type, @type_names)
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:session_id)
  end

  @doc """
  A changeset for what the job did (AI-005, AI-006).
  """
  def result_changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [:status, :output, :error, :duration_ms])
    |> validate_required([:status])
    |> validate_inclusion(:status, @status_names)
    |> update_change(:error, &String.slice(&1, 0, 500))
  end

  @doc """
  A changeset for a human's decision (AI-002).
  """
  def decision_changeset(suggestion, status, accepted_output \\ nil) do
    suggestion
    |> change(status: Atom.to_string(status))
    |> put_accepted(accepted_output)
    |> validate_inclusion(:status, @status_names)
  end

  defp put_accepted(changeset, nil), do: changeset
  defp put_accepted(changeset, output), do: put_change(changeset, :accepted_output, output)
end
