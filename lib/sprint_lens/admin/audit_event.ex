defmodule SprintLens.Admin.AuditEvent do
  @moduledoc """
  One thing an administrator did (section 6.3, AUDIT_EVENT, FR-807).

  ## What it may say

  Who, what, when, and which thing — never the content of that thing. Purging
  a session records the session's id, not its cards; erasing a user records
  the user's id, not the retrospectives they wrote in. The `detail` map goes
  through `SprintLens.Redact.payload/1` on the way in, so a caller that passes
  something personal by accident does not put it here permanently.

  There is no `updated_at` and no update function. A record of what somebody
  did is not something anybody should be able to correct.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Redact

  @type t :: %__MODULE__{}

  schema "audit_events" do
    field :action, :string
    field :target, :string
    field :detail, :string

    belongs_to :actor, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  A changeset for recording an action.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :action, :target])
    |> put_detail(attrs)
    |> validate_required([:action, :target])
    |> foreign_key_constraint(:actor_id)
  end

  @doc """
  The detail as a map again, for rendering.
  """
  @spec detail(t()) :: map()
  def detail(%__MODULE__{detail: nil}), do: %{}
  def detail(%__MODULE__{detail: json}), do: Jason.decode!(json)

  defp put_detail(changeset, attrs) do
    case attrs[:detail] || attrs["detail"] do
      nil -> changeset
      detail -> put_change(changeset, :detail, detail |> Redact.payload() |> Jason.encode!())
    end
  end
end
