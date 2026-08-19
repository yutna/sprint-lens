defmodule SprintLensWeb.Api.V1.ExportController do
  @moduledoc """
  Downloading a closed session's recap (§7.2, FR-701 to FR-703).

  A controller rather than a LiveView because the result is a file: the
  browser needs a `content-disposition` header and a body it can save, which
  is not something a socket can hand it.

  Access goes through `Insights.fetch_closed_session/2`, the same function the
  recap page uses — an export of a *live* session would be the fourth way
  around blind mode, after the API, search and the recap.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Exports
  alias SprintLens.Insights
  alias SprintLensWeb.FallbackController

  def show(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Insights.fetch_closed_session(scope(conn), session_id),
         {:ok, format} <- format(params["format"]),
         {:ok, subject} <- subject(params["of"]) do
      export = session |> Insights.recap(scope(conn)) |> Exports.render(format, subject)

      conn
      |> put_resp_content_type(export.content_type, nil)
      |> put_resp_header("content-disposition", disposition(export.filename))
      |> send_resp(:ok, export.body)
    else
      error -> refuse(conn, error)
    end
  end

  # This action is reached from two pipelines: the API, which wants the error
  # envelope, and the browser, which accepts only HTML and would raise on one.
  # A person who followed a stale link gets a page and a message.
  defp refuse(conn, error) do
    if get_format(conn) == "html" do
      conn
      |> put_flash(:error, gettext("That resource does not exist."))
      |> redirect(to: ~p"/home")
    else
      FallbackController.call(conn, error)
    end
  end

  defp format(value) do
    case Exports.parse_format(value) do
      {:ok, format} -> {:ok, format}
      :error -> {:error, :validation_failed, %{format: Enum.map(Exports.formats(), &to_string/1)}}
    end
  end

  defp subject(value) do
    case Exports.parse_subject(value) do
      {:ok, subject} -> {:ok, subject}
      :error -> {:error, :validation_failed, %{of: ["cards", "actions"]}}
    end
  end

  # RFC 6266: the plain `filename` is for clients that cannot read `filename*`,
  # and `filename*` is what carries a Thai title intact.
  defp disposition(filename) do
    ascii = String.replace(filename, ~r/[^\x20-\x7e]/, "_")

    ~s(attachment; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(filename)})
  end

  defp scope(conn), do: conn.assigns.current_scope
end
