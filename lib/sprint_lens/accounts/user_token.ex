defmodule SprintLens.Accounts.UserToken do
  @moduledoc """
  Tokens that authenticate a user: browser sessions, magic links, email
  change confirmations, and API bearer tokens.

  The session window is configurable per deployment (NFR-206) via
  `config :sprint_lens, :session_inactivity_days`. Combined with
  `SprintLensWeb.UserAuth` reissuing a token part-way through that window, the
  effect is an inactivity timeout: an active user's token keeps being renewed,
  an idle one's expires.
  """

  use Ecto.Schema

  import Ecto.Query

  alias SprintLens.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the magic link token expiry short,
  # since someone with access to the email may take over the account.
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @default_session_validity_in_days 14

  # Bearer tokens for `/api/v1` (section 7.1). Longer-lived than a browser
  # session because an integration has no one to re-authenticate it, but
  # revoked the moment the user is deactivated, exactly like a session.
  @api_token_context "api-token"
  @api_token_validity_in_days 365

  @doc """
  How long a session token stays valid without being renewed (NFR-206).
  """
  @spec session_validity_in_days() :: pos_integer()
  def session_validity_in_days do
    Application.get_env(:sprint_lens, :session_inactivity_days, @default_session_validity_in_days)
  end

  @doc """
  The context string used for API bearer tokens.
  """
  @spec api_token_context() :: String.t()
  def api_token_context, do: @api_token_context

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, SprintLens.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix's default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    days = session_validity_in_days()

    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(^days, "day"),
        # A deactivated user's existing sessions stop working on the next
        # request, which is what FR-005 means by "their sessions are revoked".
        # Their tokens are deleted as well, but this is the belt to that
        # braces: it holds even for a token issued moments before.
        where: user.is_active,
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds an API bearer token (section 7.1).

  Like a magic-link token, only the hash is stored, so a database leak does
  not hand over working credentials.
  """
  def build_api_token(user) do
    build_hashed_token(user, @api_token_context, user.email)
  end

  @doc """
  Looks up the user behind an API bearer token.

  Returns `:error` for a token that is not even valid base64, rather than
  running a pointless query.
  """
  def verify_api_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, @api_token_context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(@api_token_validity_in_days, "day"),
            where: user.is_active,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access. Furthermore, if the user changes
  their email in the system, the tokens sent to the previous email are no longer
  valid.

  Users can easily adapt the existing code to provide other types of delivery methods,
  for example, by phone numbers.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  If found, the query returns a tuple of the form `{user, token}`.

  The given token is valid if it matches its hashed counterpart in the
  database. This function also checks whether the token has expired. The context
  of a magic link token is always "login".
  """
  def verify_magic_link_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "login"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user_token found by the token, if any.

  This is used to validate requests to change the user
  email.
  The given token is valid if it matches its hashed counterpart in the
  database and if it has not expired (after @change_email_validity_in_days).
  The context must always start with "change:".
  """
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
