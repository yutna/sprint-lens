defmodule SprintLensWeb.Theme do
  @moduledoc """
  Decides which theme to render in (FR-910, FR-911).

  The order mirrors `SprintLensWeb.Locale`, and for the same reasons:

    1. the signed-in user's saved choice, so it follows them between devices
       (FR-003, FR-911);
    2. a choice made in this browser session by someone with no account yet,
       stored in the session cookie by `SprintLensWeb.ThemeController`;
    3. `system`, which the client resolves against the operating system
       because the server cannot know it.

  There is no `accept-*` header step: `prefers-color-scheme` is a CSS media
  query, not a request header, so `system` is the server's honest answer and
  the browser finishes the sentence.
  """

  alias SprintLens.Accounts.User

  @system "system"

  @doc """
  The themes the UI offers.
  """
  @spec supported() :: [String.t()]
  def supported, do: User.themes()

  @doc """
  Whether a value names a theme the UI supports.
  """
  @spec supported?(term()) :: boolean()
  def supported?(theme), do: is_binary(theme) and theme in User.themes()

  @doc """
  Picks a theme from a user and a session choice, either of which may be
  absent.
  """
  @spec resolve(map() | nil, term()) :: String.t()
  def resolve(user, session_theme \\ nil)

  def resolve(%{theme: theme}, session_theme) do
    if supported?(theme), do: theme, else: resolve(nil, session_theme)
  end

  def resolve(_user, session_theme) do
    if supported?(session_theme), do: session_theme, else: @system
  end
end
