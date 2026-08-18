defmodule SprintLensWeb.LocaleController do
  @moduledoc """
  Stores a language choice for a visitor who has no profile to store it in
  (FR-907).

  A signed-in user's language lives on their profile and a LiveView can write
  it directly. A signed-out visitor has only the session cookie, which a
  LiveView cannot write, so the switcher sends them through here and straight
  back to where they were.
  """

  use SprintLensWeb, :controller

  alias SprintLensWeb.Locale

  def update(conn, %{"language" => language} = params) do
    conn = if Locale.supported?(language), do: put_session(conn, :locale, language), else: conn

    redirect(conn, to: return_to(params))
  end

  # Only same-site paths: an open redirect here would let a crafted "change
  # language" link bounce a visitor to another host.
  defp return_to(%{"return_to" => "/" <> _rest = path}) do
    if String.starts_with?(path, "//"), do: ~p"/", else: path
  end

  defp return_to(_params), do: ~p"/"
end
