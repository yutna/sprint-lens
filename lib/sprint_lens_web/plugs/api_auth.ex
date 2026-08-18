defmodule SprintLensWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates `/api/v1` requests with a bearer token (section 7.1).

  Every API call except the health probe passes through here, and every one of
  them is rate limited per user and per IP first (NFR-202). A deactivated
  user's token stops resolving the moment they are deactivated (FR-005), which
  is handled in the token query itself rather than here.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias SprintLens.Accounts
  alias SprintLens.Accounts.Scope
  alias SprintLens.RateLimit
  alias SprintLensWeb.ApiError
  alias SprintLensWeb.Locale
  alias SprintLensWeb.Plugs.RequestContext

  @impl Plug
  def init(opts), do: Keyword.get(opts, :bucket, :api)

  @impl Plug
  def call(conn, bucket) do
    with {:ok, token} <- bearer_token(conn),
         %{} = user <- Accounts.get_user_by_api_token(token),
         :ok <- RateLimit.check(bucket, user.id, client_ip(conn)) do
      RequestContext.put_user(user)
      Locale.put(user.language)

      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:locale, user.language)
    else
      {:error, :rate_limited, retry_after} -> deny(conn, :rate_limited, retry_after)
      _unauthenticated -> deny(conn, :unauthenticated, nil)
    end
  end

  @doc """
  Extracts the bearer token from the `authorization` header.
  """
  @spec bearer_token(Plug.Conn.t()) :: {:ok, String.t()} | :error
  def bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _rest] when byte_size(token) > 0 -> {:ok, String.trim(token)}
      ["bearer " <> token | _rest] when byte_size(token) > 0 -> {:ok, String.trim(token)}
      _missing_or_malformed -> :error
    end
  end

  defp deny(conn, :rate_limited, retry_after) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(div(retry_after, 1000) + 1))
    |> respond(:rate_limited, %{retry_after_ms: retry_after})
  end

  defp deny(conn, code, _detail), do: respond(conn, code, %{})

  defp respond(conn, code, details) do
    conn
    |> put_status(ApiError.status(code))
    |> json(ApiError.envelope(code, ApiError.message(code), details))
    |> halt()
  end

  defp client_ip(conn), do: conn.remote_ip
end
