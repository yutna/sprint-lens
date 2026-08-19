defmodule SprintLensWeb.Api.V1.SuggestionController do
  @moduledoc """
  Asking for a suggestion and polling for it (§7.2, AI-005).

  §7.2 gives two lines: `POST /sessions/{id}/suggestions` and
  `GET /suggestions/{id}`. AI-005 says the UI "polls or receives an event
  when a suggestion is ready" — the screens receive the event; this is the
  polling half, for anything that is not a browser.

  The decision endpoints are additions under §7.2's "implementations may add
  endpoints" clause, because AI-002's accept-or-reject has to be reachable
  from something other than a LiveView for the API to be usable at all.
  """

  use SprintLensWeb, :controller

  alias SprintLens.AI
  alias SprintLens.AI.Suggestion
  alias SprintLens.Retro
  alias SprintLensWeb.Api.V1.SuggestionJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def create(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, type} <- fetch_type(params["type"]),
         {:ok, suggestion} <-
           AI.request(scope(conn), session.team, type, context(session, params)) do
      conn
      |> put_status(:accepted)
      |> json(%{data: SuggestionJSON.suggestion(suggestion)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, suggestion} <- AI.fetch_suggestion(scope(conn), id) do
      json(conn, %{data: SuggestionJSON.suggestion(suggestion)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, suggestion} <- AI.fetch_suggestion(scope(conn), id),
         {:ok, decided} <- decide(conn, suggestion, params) do
      json(conn, %{data: SuggestionJSON.suggestion(decided)})
    end
  end

  # One endpoint for the three things AI-002 allows: accept as it stands,
  # accept an edited version, or reject.
  defp decide(conn, suggestion, %{"action" => "accept"} = params) do
    AI.accept(scope(conn), suggestion, params["output"])
  end

  defp decide(conn, suggestion, %{"action" => "reject"}) do
    AI.reject(scope(conn), suggestion)
  end

  defp decide(conn, suggestion, %{"action" => "retry"}) do
    AI.retry(scope(conn), suggestion)
  end

  defp decide(_conn, _suggestion, _params) do
    {:error, :validation_failed, %{action: ["accept", "reject", "retry"]}}
  end

  defp fetch_type(value) do
    case Suggestion.parse_type(value) do
      {:ok, type} ->
        {:ok, type}

      :error ->
        {:error, :validation_failed, %{type: Enum.map(Suggestion.types(), &to_string/1)}}
    end
  end

  defp context(session, params) do
    %{session: session}
    |> maybe_put(:topic, params["topic"])
    |> maybe_put(:note, params["note"])
    |> maybe_put(:text, params["text"])
    |> maybe_put(:language, params["language"])
  end

  defp maybe_put(context, _key, nil), do: context
  defp maybe_put(context, key, value), do: Map.put(context, key, value)

  defp scope(conn), do: conn.assigns.current_scope
end
