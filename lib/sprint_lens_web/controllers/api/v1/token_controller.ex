defmodule SprintLensWeb.Api.V1.TokenController do
  @moduledoc """
  Exchanges an email and password for an API bearer token (FR-001, §7.1).

  Rate limited on the `:auth` bucket, which is far tighter than the general
  API bucket, because this is the endpoint worth brute-forcing (NFR-202).
  The response is the same for an unknown email and a wrong password.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Accounts
  alias SprintLens.RateLimit
  alias SprintLensWeb.ApiError

  def create(conn, params) do
    %{"email" => email, "password" => password} = credentials(params)

    with :ok <- RateLimit.check(:auth, email, conn.remote_ip),
         %{} = user <- Accounts.get_user_by_email_and_password(email, password),
         true <- user.is_active do
      json(conn, %{data: %{token: Accounts.create_api_token(user), token_type: "bearer"}})
    else
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(retry_after, 1000) + 1))
        |> error(:rate_limited, %{retry_after_ms: retry_after})

      _invalid ->
        error(conn, :invalid_credentials, %{})
    end
  end

  defp credentials(%{"user" => %{} = user}), do: credentials(user)

  defp credentials(params) do
    %{
      "email" => to_string(params["email"] || ""),
      "password" => to_string(params["password"] || "")
    }
  end

  defp error(conn, code, details) do
    conn
    |> put_status(ApiError.status(code))
    |> json(ApiError.envelope(code, ApiError.message(code), details))
  end
end
