defmodule SprintLensWeb.ErrorJSON do
  @moduledoc """
  Renders errors that never reached a controller — a route that does not
  exist, a crash, a malformed request.

  These use the same envelope as every deliberate API error (§7.1), so a
  client only ever has to parse one error shape. The message stays generic:
  technical detail goes to the logs, not to the user (FR-919).
  """

  alias SprintLensWeb.ApiError

  @doc """
  Maps an HTTP status template to the spec's error envelope.
  """
  def render(template, _assigns) do
    code = code_for(template)

    ApiError.envelope(code, ApiError.message(code))
  end

  defp code_for("400" <> _rest), do: :validation_failed
  defp code_for("401" <> _rest), do: :unauthenticated
  defp code_for("403" <> _rest), do: :forbidden
  defp code_for("404" <> _rest), do: :not_found
  defp code_for("409" <> _rest), do: :conflict
  defp code_for("422" <> _rest), do: :validation_failed
  defp code_for("429" <> _rest), do: :rate_limited
  defp code_for("503" <> _rest), do: :dependency_unavailable
  defp code_for(_template), do: :internal_error
end
