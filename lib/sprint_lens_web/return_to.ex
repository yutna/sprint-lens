defmodule SprintLensWeb.ReturnTo do
  @moduledoc """
  Resolves the `return_to` parameter the preference controllers redirect to.

  Both the language and the theme switcher are ordinary links that send the
  visitor through a controller and straight back to where they were, so both
  need the same guard, and there is exactly one implementation of it here
  rather than one per controller (NFR-203).

  Only a same-site absolute path is accepted. A protocol-relative path is
  rejected because `//evil.example.com` is a URL to another host that happens
  to begin with a slash, and an open redirect on a link labelled "change
  language" is a phishing primitive.
  """

  @home "/"

  @doc """
  The path to return to, or the home page when the parameter is missing or
  is not a same-site path.
  """
  @spec path(map()) :: String.t()
  def path(%{"return_to" => "/" <> _rest = path}) do
    if String.starts_with?(path, "//"), do: @home, else: path
  end

  def path(_params), do: @home
end
