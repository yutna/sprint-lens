defmodule SprintLens.UnitCase do
  @moduledoc """
  Test case for code that touches no database.

  Policy decisions, serializers, changeset validation, formatters, pure
  calculations. These run `async: true` and are where the suite gets its
  parallelism, since `SprintLens.DataCase` has to run serially (see its
  moduledoc for why).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Changeset
      import SprintLens.UnitCase
    end
  end

  @doc """
  Transforms changeset errors into a map of messages, the same shape
  `SprintLens.DataCase.errors_on/1` returns, so an assertion reads the same
  whether or not the test needed a database.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
