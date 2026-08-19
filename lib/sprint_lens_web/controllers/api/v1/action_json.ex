defmodule SprintLensWeb.Api.V1.ActionJSON do
  @moduledoc """
  Serialises action items (§7.2).
  """

  alias SprintLens.Actions.ActionItem
  alias SprintLensWeb.Api.V1.UserJSON

  @doc """
  One action item.
  """
  @spec action(ActionItem.t()) :: map()
  def action(%ActionItem{} = item) do
    %{
      id: item.id,
      title: item.title,
      description: item.description,
      status: item.status,
      due_date: item.due_date,
      team_id: item.team_id,
      session_id: item.session_id,
      card_id: item.card_id,
      card_group_id: item.card_group_id,
      # The link FR-505 asks to be kept, so a client can show where a carried
      # commitment came from.
      carried_from_id: item.carried_from_id,
      # Always preloaded by the context, so this is a user or nothing.
      assignee: UserJSON.summary(item.assignee),
      created_at: item.inserted_at,
      updated_at: item.updated_at
    }
  end
end
