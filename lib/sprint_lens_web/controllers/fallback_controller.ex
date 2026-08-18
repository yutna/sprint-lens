defmodule SprintLensWeb.FallbackController do
  @moduledoc """
  Turns the error tuples contexts return into the API error envelope (§7.1).

  Every API controller delegates here, so a new failure mode has to be given a
  name in `SprintLensWeb.ApiError` rather than escaping as an untyped 500
  (FR-919, NFR-201).
  """

  use SprintLensWeb, :controller

  alias Ecto.Changeset
  alias SprintLensWeb.ApiError
  alias SprintLensWeb.CoreComponents

  def call(conn, {:error, %Changeset{} = changeset}) do
    respond(conn, :validation_failed, %{fields: changeset_errors(changeset)})
  end

  def call(conn, {:error, :not_found}), do: respond(conn, :not_found, %{})
  def call(conn, {:error, :unauthorized}), do: respond(conn, :forbidden, %{})

  def call(conn, {:error, code, details}) when is_atom(code) and is_map(details) do
    respond(conn, code, details)
  end

  def call(conn, {:error, code}) when is_atom(code), do: respond(conn, code, %{})
  def call(conn, nil), do: respond(conn, :not_found, %{})

  @doc """
  Flattens changeset errors to `%{field => [message]}`, translated.
  """
  @spec changeset_errors(Changeset.t()) :: map()
  def changeset_errors(changeset) do
    Changeset.traverse_errors(changeset, &CoreComponents.translate_error/1)
  end

  defp respond(conn, code, details) do
    conn
    |> put_status(ApiError.status(code))
    |> json(ApiError.envelope(code, ApiError.message(code), details))
  end
end
