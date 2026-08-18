defmodule SprintLens.Accounts.User do
  @moduledoc """
  A person who can sign in (spec section 6.3, USER).

  Carries authentication state plus the profile FR-003 requires: display name,
  optional avatar, preferred language and theme. `is_org_admin` is the
  org-level role from section 3.1; `is_active` is what FR-005 flips when an
  Org Admin deactivates someone.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @languages ~w(th en)
  @themes ~w(light dark system)

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    field :display_name, :string
    field :avatar_url, :string
    field :language, :string, default: "th"
    field :theme, :string, default: "system"

    field :is_org_admin, :boolean, default: false
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  The languages the UI is available in (FR-906). Thai is the default.
  """
  @spec languages() :: [String.t()]
  def languages, do: @languages

  @doc """
  The theme choices (FR-910). `system` follows the operating system.
  """
  @spec themes() :: [String.t()]
  def themes, do: @themes

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  A changeset for registering a new account.

  Registration collects the display name alongside the email, because every
  screen that shows a card, a vote or a presence indicator needs a name to put
  next to it (FR-003). Language and theme fall back to the org defaults.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :display_name])
    |> validate_email(opts)
    |> validate_display_name()
  end

  @doc """
  A changeset for the profile fields a user controls themselves (FR-003).

  Deliberately does not cast `is_org_admin` or `is_active`: those are
  org-level decisions made by an Org Admin (FR-005, FR-801), not preferences.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :avatar_url, :language, :theme])
    |> validate_display_name()
    |> validate_inclusion(:language, @languages)
    |> validate_inclusion(:theme, @themes)
    |> validate_length(:avatar_url, max: 500)
  end

  @doc """
  A changeset for the org-level flags only an Org Admin may set.
  """
  def admin_changeset(user, attrs) do
    cast(user, attrs, [:is_org_admin, :is_active])
  end

  defp validate_display_name(changeset) do
    changeset
    |> validate_required([:display_name])
    |> update_change(:display_name, &String.trim/1)
    |> validate_length(:display_name, min: 1, max: 80)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, SprintLens.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%SprintLens.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
