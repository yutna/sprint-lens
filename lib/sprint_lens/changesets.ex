defmodule SprintLens.Changesets do
  @moduledoc """
  Small changeset helpers shared by every schema.

  ## Why `trim/2` exists

  `update_change(changeset, :title, &String.trim/1)` looks harmless and is not.
  `Ecto.Changeset.cast/4` treats a whitespace-only parameter as empty and casts
  it to `nil`. On a *new* record that is no change at all, so the trim never
  runs and `validate_required/2` reports the blank field. On an *edit*, where
  the field already holds something, `nil` differs from the current value, so
  it is recorded as a change — and `String.trim/1` is handed `nil` and raises.

  The result is that clearing any field crashes while creating one blank is
  handled politely, which is exactly backwards. It only shows up on the edit
  path, which is why it survived several milestones here.
  """

  import Ecto.Changeset

  @doc """
  Trims a string change, leaving `nil` alone for `validate_required/2` to
  report.
  """
  @spec trim(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def trim(changeset, field) do
    update_change(changeset, field, fn
      nil -> nil
      value -> String.trim(value)
    end)
  end
end
