defmodule SprintLensWeb.Plugs.RequestContext do
  @moduledoc """
  Puts the request correlation id into `Logger` metadata so every line emitted
  while handling a request can be tied back to it (NFR-502).

  `Plug.RequestId` (already in the endpoint) generates the id and sets the
  `x-request-id` response header. This plug lifts it into logger metadata
  along with the route, and — once a user is assigned — their id. Never the
  user's email or name: that is personal data and stays out of logs.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Logger.metadata(
      request_id: request_id(conn),
      method: conn.method,
      path: conn.request_path
    )

    Plug.Conn.register_before_send(conn, fn conn ->
      Logger.metadata(status: conn.status)
      conn
    end)
  end

  @doc """
  Records the acting user on the current process's logger metadata.

  Called once authentication has resolved a user, and from LiveView `mount/3`
  where there is no plug pipeline to hook into.
  """
  @spec put_user(term() | nil) :: :ok
  def put_user(nil), do: :ok
  def put_user(%{id: id}), do: Logger.metadata(user_id: id)
  def put_user(id), do: Logger.metadata(user_id: id)

  defp request_id(conn) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [id | _rest] -> id
      [] -> Logger.metadata()[:request_id]
    end
  end
end
