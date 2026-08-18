defmodule SprintLensWeb.Api.V1.HealthController do
  @moduledoc """
  `GET /api/v1/health` — the one endpoint that does not require
  authentication (§7.1), reporting on critical dependencies (NFR-501).

  `?probe=live` answers liveness only; the default answers readiness.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Health

  def show(conn, params) do
    report =
      case params["probe"] do
        "live" -> Health.alive()
        _readiness -> Health.ready()
      end

    conn
    |> put_status(Health.http_status(report))
    |> json(render_report(report))
  end

  defp render_report(report) do
    %{
      status: report.status,
      checks:
        Enum.map(report.checks, fn check ->
          %{name: check.name, status: check.status, detail: check.detail}
        end)
    }
  end
end
