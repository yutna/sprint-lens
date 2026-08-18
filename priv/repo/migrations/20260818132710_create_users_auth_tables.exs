defmodule SprintLens.Repo.Migrations.CreateUsersAuthTables do
  @moduledoc """
  Users and their authentication tokens.

  Beyond what `phx.gen.auth` needs, the `users` table carries the profile and
  org-level fields the spec's USER entity defines (section 6.3): a display
  name, an optional avatar, language and theme preferences (FR-003), the
  org-admin flag, and the active flag that FR-005 flips.
  """

  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false, collate: :nocase
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      # Profile (FR-003). Thai is the default for new users (FR-906).
      add :display_name, :string, null: false
      add :avatar_url, :string
      add :language, :string, null: false, default: "th"
      add :theme, :string, null: false, default: "system"

      # Organisation-level flags (section 3.1, FR-005).
      add :is_org_admin, :boolean, null: false, default: false
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false, size: 32
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
