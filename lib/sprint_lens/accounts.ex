defmodule SprintLens.Accounts do
  @moduledoc """
  Users, authentication and profiles (spec sections 4.1 and 6.3).

  Authentication is deliberately kept behind this context so a deployment can
  swap the baseline for an identity provider without the rest of the app
  noticing (FR-002).
  """

  import Ecto.Query, warn: false

  alias SprintLens.Accounts.User
  alias SprintLens.Accounts.UserNotifier
  alias SprintLens.Accounts.UserToken
  alias SprintLens.Repo

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{language: default_language()}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  The organisation-wide default language new accounts start in (FR-802,
  FR-906). Thai unless an Org Admin changes it.
  """
  @spec default_language() :: String.t()
  def default_language do
    language = Application.get_env(:sprint_lens, :default_language, "th")

    if language in User.languages(), do: language, else: "th"
  end

  @doc """
  A changeset for the registration form.
  """
  def change_user_registration(user \\ %User{}, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  ## Profile (FR-003)

  @doc """
  A changeset for the profile form.
  """
  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the display name, avatar, language and theme a user controls
  themselves (FR-003, FR-907, FR-911).
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  ## Administration (FR-005, FR-801)

  @doc """
  Every user in the organisation, newest first.
  """
  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  @doc """
  Deactivates a user (FR-005).

  Deleting their tokens in the same transaction is what makes "their sessions
  are revoked" true immediately rather than at the next expiry (NFR-206).
  Their content stays put — the retention policy decides its fate, not this.
  """
  def deactivate_user(%User{} = user) do
    Repo.transact(fn ->
      with {:ok, user} <- user |> User.admin_changeset(%{is_active: false}) |> Repo.update() do
        Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id))
        {:ok, user}
      end
    end)
  end

  @doc """
  Restores a deactivated user's ability to sign in. They start with no
  sessions, so they have to authenticate again.
  """
  def activate_user(%User{} = user) do
    user
    |> User.admin_changeset(%{is_active: true})
    |> Repo.update()
  end

  @doc """
  Grants or revokes org-admin rights (FR-801).
  """
  def set_org_admin(%User{} = user, is_org_admin) when is_boolean(is_org_admin) do
    user
    |> User.admin_changeset(%{is_org_admin: is_org_admin})
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `SprintLens.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `SprintLens.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Delivers password reset instructions (FR-004).

  Uses the same short-lived login token as the magic link: the user signs in
  from the emailed link and then sets a new password from inside their
  session, so a stale link can never set a password on its own.
  """
  def deliver_password_reset_instructions(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_password_reset_instructions(user, reset_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## API tokens (section 7.1)

  @doc """
  Issues a bearer token for `/api/v1`.

  Returns the plaintext token — the only time it is ever available, since only
  its hash is stored.
  """
  def create_api_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_api_token(user)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Resolves a bearer token to its user, or `nil` if the token is unknown,
  expired, malformed, or belongs to a deactivated user (FR-005).
  """
  def get_user_by_api_token(token) when is_binary(token) do
    case UserToken.verify_api_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def get_user_by_api_token(_token), do: nil

  @doc """
  Revokes every API token belonging to a user.
  """
  def revoke_api_tokens(%User{} = user) do
    context = UserToken.api_token_context()

    {count, _} =
      Repo.delete_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == ^context)
      )

    count
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
