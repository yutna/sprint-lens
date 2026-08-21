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

  setup tags do
    pin_locale(tags)
    :ok
  end

  @doc """
  Pins the interface language for a test module.

  The interface is Thai first and Gettext's default now says so, so a test
  that asserts on English copy has to ask for it:

      @moduletag locale: "en"

  Only the calling process's locale is set, never the application
  environment. These tests run `async: true`, and an application environment
  is global: one module pinning it would change the language underneath every
  other module running at the same time. `SprintLensWeb.ConnCase` can afford
  to pin both because its tests are serial.
  """
  def pin_locale(%{locale: locale}) do
    SprintLensWeb.Locale.put(locale)
  end

  def pin_locale(_tags), do: :ok

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
