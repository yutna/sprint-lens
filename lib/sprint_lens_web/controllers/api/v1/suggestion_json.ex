defmodule SprintLensWeb.Api.V1.SuggestionJSON do
  @moduledoc """
  Serialises a suggestion as §5.2's envelope.

  The shape is the spec's, field for field: id, type, team, session, status,
  input scope, output and when it was made. `output` is `null` until the job
  finishes, which is what a client polling for it is watching.
  """

  alias SprintLens.AI.Suggestion

  @doc """
  One suggestion, in §5.2's envelope.
  """
  @spec suggestion(Suggestion.t()) :: map()
  def suggestion(%Suggestion{} = suggestion) do
    %{
      id: suggestion.id,
      type: suggestion.type,
      team_id: suggestion.team_id,
      session_id: suggestion.session_id,
      status: suggestion.status,
      input_scope: Suggestion.input_scope(suggestion),
      output: output(suggestion),
      error: suggestion.error,
      # AI-014: a translation is "marked as machine translated". The mark
      # travels with the output rather than being left to a client to
      # remember, because the client that forgets is the one that matters.
      machine_translated: suggestion.type == "translation",
      created_at: suggestion.inserted_at
    }
  end

  # The accepted text once there is one: a client asking what the team agreed
  # should get the human's version, not the model's first draft (AI-002).
  defp output(%Suggestion{output: nil}), do: nil

  defp output(%Suggestion{} = suggestion) do
    %{format: format(suggestion), content: suggestion.accepted_output || suggestion.output}
  end

  defp format(%Suggestion{type: type}) when type in ~w(clustering icebreakers), do: "json"
  defp format(_suggestion), do: "markdown"
end
