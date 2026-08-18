defmodule SprintLensWeb.ApiError do
  @moduledoc """
  The single error envelope shape every `/api/v1` response uses (§7.1):

      {"error": {"code": "...", "message": "...", "details": {...}}}

  `code` is a stable machine-readable slug; `message` is human-readable and
  translated; `details` carries whatever the client needs to recover, such as
  the vote budget it exceeded. Technical detail belongs in the logs, not here
  (FR-919).
  """

  use Gettext, backend: SprintLensWeb.Gettext

  @type code :: atom()

  # Every error code the API can return, with its HTTP status. Keeping them in
  # one place means a new failure mode has to be named deliberately rather
  # than leaking a stack trace.
  @codes %{
    unauthenticated: 401,
    invalid_credentials: 401,
    forbidden: 403,
    not_found: 404,
    conflict: 409,
    validation_failed: 422,
    vote_budget_exceeded: 422,
    wrong_phase: 422,
    session_closed: 422,
    team_archived: 422,
    ai_disabled: 422,
    webhooks_disabled: 422,
    rate_limited: 429,
    internal_error: 500,
    dependency_unavailable: 503
  }

  @doc """
  The HTTP status for an error code.
  """
  @spec status(code()) :: pos_integer()
  def status(code), do: Map.fetch!(@codes, code)

  @doc """
  Every known error code. Used by tests to assert the table stays exhaustive.
  """
  @spec codes() :: [code()]
  def codes, do: Map.keys(@codes)

  @doc """
  Builds the envelope body. `details` is omitted entirely when empty rather
  than serialised as `null`, so clients can branch on its presence.
  """
  @spec envelope(code(), String.t(), map()) :: map()
  def envelope(code, message, details \\ %{}) do
    error =
      %{code: Atom.to_string(code), message: message}
      |> maybe_put_details(details)

    %{error: error}
  end

  @doc """
  The default human-readable message for a code, in the caller's language.
  """
  @spec message(code()) :: String.t()
  def message(:unauthenticated), do: gettext("You must be signed in to do that.")
  def message(:invalid_credentials), do: gettext("That email and password do not match.")
  def message(:forbidden), do: gettext("You do not have permission to do that.")
  def message(:not_found), do: gettext("That resource does not exist.")
  def message(:conflict), do: gettext("That change conflicts with the current state.")
  def message(:validation_failed), do: gettext("Some fields need attention.")
  def message(:vote_budget_exceeded), do: gettext("You have no votes left in this session.")
  def message(:wrong_phase), do: gettext("That action is not available in this phase.")
  def message(:session_closed), do: gettext("This session is closed.")
  def message(:team_archived), do: gettext("This team is archived and read-only.")
  def message(:ai_disabled), do: gettext("AI features are turned off.")
  def message(:webhooks_disabled), do: gettext("Webhooks are turned off.")
  def message(:rate_limited), do: gettext("Too many requests. Please slow down.")
  def message(:internal_error), do: gettext("Something went wrong on our side.")
  def message(:dependency_unavailable), do: gettext("A required service is unavailable.")

  defp maybe_put_details(error, details) when details == %{}, do: error
  defp maybe_put_details(error, details), do: Map.put(error, :details, details)
end
