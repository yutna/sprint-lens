defmodule SprintLens.Factory do
  @moduledoc """
  Test data builders.

  Factories produce the *minimum valid* record. Anything a test cares about it
  states explicitly in the overrides, so a test reads as a description of the
  case it covers rather than of the fixture. Grows one factory per schema as
  the milestones land.
  """

  use ExMachina.Ecto, repo: SprintLens.Repo

  @doc """
  A value unique to this call, for fields with a uniqueness constraint.
  """
  def unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
