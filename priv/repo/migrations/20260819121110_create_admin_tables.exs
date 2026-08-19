defmodule SprintLens.Repo.Migrations.CreateAdminTables do
  @moduledoc """
  Organisation settings and the audit log (section 6.3 ORG_SETTINGS and
  AUDIT_EVENT, FR-802 and FR-807).

  ## The singleton is seeded here, not created on demand

  ORG_SETTINGS is a singleton, and the two ways to make one are "get or
  create" and "it is always there". The second has no race and no branch: the
  row is inserted in the same transaction that creates the table, so
  `SprintLens.Admin.settings/0` is a plain read that cannot fail. The defaults
  are section 6.3's, including Thai as the default language (FR-802, FR-906).

  ## The audit log has no `updated_at`

  A record of what somebody did is not something anybody should be able to
  correct. There is no update path in the context either — the absence is the
  guarantee (FR-807).
  """

  use Ecto.Migration

  # Section 6.3's ORG_SETTINGS defaults, and FR-802's "default th".
  @default_language "th"
  @default_vote_budget 5
  @default_retention_days 365

  def change do
    create table(:org_settings) do
      add :default_language, :string, null: false, default: @default_language
      add :default_vote_budget, :integer, null: false, default: @default_vote_budget
      add :retention_days, :integer, null: false, default: @default_retention_days
      add :ai_enabled, :boolean, null: false, default: true
      add :webhooks_enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    execute(&seed_settings/0, fn -> :ok end)

    create table(:audit_events) do
      # Nullable: erasing a person (FR-805) removes who they were without
      # removing the record that something was done.
      add :actor_id, references(:users, on_delete: :nilify_all)

      add :action, :string, null: false
      add :target, :string, null: false
      add :detail, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:inserted_at])
    create index(:audit_events, [:actor_id])
    create index(:audit_events, [:action])
  end

  defp seed_settings do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

    repo().insert_all("org_settings", [
      %{
        id: 1,
        default_language: @default_language,
        default_vote_budget: @default_vote_budget,
        retention_days: @default_retention_days,
        ai_enabled: 1,
        webhooks_enabled: 1,
        inserted_at: now,
        updated_at: now
      }
    ])
  end
end
