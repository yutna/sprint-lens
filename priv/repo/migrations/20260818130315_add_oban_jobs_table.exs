defmodule SprintLens.Repo.Migrations.AddObanJobsTable do
  @moduledoc """
  Oban's job storage. Backs webhook delivery retries (FR-706), the scheduled
  retention purge (FR-803) and asynchronous AI jobs (AI-005).
  """

  use Ecto.Migration

  def up do
    Oban.Migration.up()
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
