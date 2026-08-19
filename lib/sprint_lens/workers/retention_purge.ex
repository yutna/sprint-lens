defmodule SprintLens.Workers.RetentionPurge do
  @moduledoc """
  Deletes closed sessions that are older than the organisation's retention
  period (FR-803, NFR-302).

  The purging itself is `SprintLens.Admin.purge_session/2`, the same function
  an administrator's button calls (FR-804). One code path means the audit row,
  the cascade and the refusal to purge a live session are the same whether a
  person or the clock started it — and the audit log says which, because the
  scheduled sweep passes `:system` as its actor.
  """

  use Oban.Worker, queue: :retention, max_attempts: 3

  alias SprintLens.Admin

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = parse_now(args["now"])

    purged =
      now
      |> Admin.expired_sessions()
      |> Enum.map(&Admin.purge_session(:system, &1))
      |> Enum.count(&match?({:ok, _session}, &1))

    {:ok, purged}
  end

  # The job carries its own clock so a test can say "pretend a year has
  # passed" without waiting for one.
  defp parse_now(nil), do: DateTime.utc_now()

  defp parse_now(iso8601) do
    {:ok, now, _offset} = DateTime.from_iso8601(iso8601)
    now
  end
end
