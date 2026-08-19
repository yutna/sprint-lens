defmodule SprintLens.Workers.ActionDueSweep do
  @moduledoc """
  Notices which action items have reached their due date, once each
  (FR-704).

  ## Once, not every morning

  A daily sweep that announced everything still open would send the same
  reminder every day until somebody closed the item, and a channel that
  repeats itself is a channel people mute. So an item is marked
  `due_notified_at` when it is announced, and the sweep skips anything that
  already has one.

  That also makes the behaviour testable as a fact rather than a hope: run the
  sweep twice, and the second run announces nothing.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query, warn: false

  alias SprintLens.Actions.ActionItem
  alias SprintLens.Repo
  alias SprintLens.Webhooks

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = parse_now(args["now"])

    due(now)
    |> Enum.each(fn action ->
      Webhooks.action_due(action)
      mark_notified(action, now)
    end)

    :ok
  end

  @doc """
  The items that are due and have not been announced yet.
  """
  @spec due(DateTime.t()) :: [ActionItem.t()]
  def due(now \\ DateTime.utc_now()) do
    live = Enum.map(ActionItem.live_statuses(), &Atom.to_string/1)

    Repo.all(
      from a in ActionItem,
        where: a.status in ^live,
        where: not is_nil(a.due_date) and a.due_date <= ^now,
        where: is_nil(a.due_notified_at),
        order_by: [asc: a.due_date, asc: a.id],
        preload: [:assignee]
    )
  end

  defp mark_notified(action, now) do
    Repo.update_all(
      from(a in ActionItem, where: a.id == ^action.id),
      set: [due_notified_at: DateTime.truncate(now, :second)]
    )
  end

  # The job carries its own clock so a test can say "pretend it is next week"
  # without waiting for it.
  defp parse_now(nil), do: DateTime.utc_now()

  defp parse_now(iso8601) do
    {:ok, now, _offset} = DateTime.from_iso8601(iso8601)
    now
  end
end
