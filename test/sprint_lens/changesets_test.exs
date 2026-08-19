defmodule SprintLens.ChangesetsTest do
  @moduledoc """
  The shared changeset helpers, and the trap they exist for.
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Changesets
  alias SprintLens.Retro.Card

  @tag req: ["FR-919"]
  test "a change is trimmed" do
    changeset =
      %Card{}
      |> Ecto.Changeset.cast(%{"text" => "  hello  "}, [:text])
      |> Changesets.trim(:text)

    assert get_change(changeset, :text) == "hello"
  end

  @tag req: ["FR-919"]
  test "clearing a field that already had a value does not crash" do
    # `cast/4` reads a whitespace-only parameter as empty and casts it to nil.
    # On an existing record that *is* a change, so a bare `&String.trim/1`
    # here is handed nil and raises — which made clearing any field a 500
    # while creating one blank was handled politely.
    changeset =
      %Card{text: "already here"}
      |> Ecto.Changeset.cast(%{"text" => "   "}, [:text])
      |> Changesets.trim(:text)

    assert get_change(changeset, :text) == nil
    assert changeset |> validate_required([:text]) |> Map.fetch!(:valid?) == false
  end

  @tag req: ["FR-919"]
  test "a field nobody touched is left alone" do
    changeset =
      %Card{text: "already here"}
      |> Ecto.Changeset.cast(%{}, [:text])
      |> Changesets.trim(:text)

    assert changeset.changes == %{}
  end
end
