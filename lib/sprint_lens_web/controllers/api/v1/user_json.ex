defmodule SprintLensWeb.Api.V1.UserJSON do
  @moduledoc """
  Serialises users for the API.

  Two shapes, deliberately different:

    * `profile/1` is what a user sees about themselves — their preferences and
      their org-admin flag.
    * `summary/1` is what other people see — the identity needed to put a name
      next to a card or an assignee, and nothing else. Email addresses are
      personal data and do not belong in a teammate-facing payload.
  """

  alias SprintLens.Accounts.User

  @doc """
  The current user's own profile.
  """
  @spec profile(User.t() | map()) :: map()
  def profile(user) do
    %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      language: user.language,
      theme: user.theme,
      is_org_admin: user.is_org_admin,
      is_active: user.is_active,
      confirmed_at: user.confirmed_at
    }
  end

  @doc """
  A teammate's public identity.
  """
  @spec summary(User.t() | map() | nil) :: map() | nil
  def summary(nil), do: nil

  def summary(user) do
    %{id: user.id, display_name: user.display_name, avatar_url: user.avatar_url}
  end
end
