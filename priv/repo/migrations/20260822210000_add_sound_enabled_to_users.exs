defmodule SprintLens.Repo.Migrations.AddSoundEnabledToUsers do
  @moduledoc """
  The sound preference (FR-921).

  Off for everybody, including everybody who already exists. A retrospective
  is usually held on a video call, where a sound the tool makes is a sound the
  whole room hears — so nobody gets it without asking for it.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :sound_enabled, :boolean, null: false, default: false
    end
  end
end
