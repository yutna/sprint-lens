defmodule SprintLens.Repo.Migrations.AddParticipantCountToSessions do
  @moduledoc """
  How many people took part, counted once and kept.

  ## Why this is a stored number rather than a query

  FR-601 wants the archive to show a participant count and FR-604 wants a
  participation rate across sessions. Both would normally be a `count(distinct
  ...)` over who wrote cards, cast votes and answered the mood question.

  For an anonymous session those references are destroyed when it closes
  (section 6.4, NFR-304), so after the fact there is nothing left to count.
  Section 6.4 anticipates exactly this: "aggregates built from them remain,
  de-identified". So the count is taken in the same transaction that closes
  the session, immediately before the references are stripped — a number that
  says how many people were there and nothing about who.

  Section 6.3 does not list this field. It is not a new fact about a session;
  it is the only surviving form of one the spec's own retention rules destroy.
  """

  use Ecto.Migration

  def change do
    alter table(:retro_sessions) do
      add :participant_count, :integer
    end
  end
end
