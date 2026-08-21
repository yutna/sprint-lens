defmodule SprintLens.Accounts.UserNotifier do
  @moduledoc """
  Transactional email for the baseline authentication method (FR-001, FR-004).

  ## Why the locale is set here

  A notification is generated for one specific person, and it is generated
  outside a browser request — from a LiveView process, or from a background
  job. Neither carries the recipient's language. Left alone, Gettext would use
  whatever locale the sending process happened to hold, which is the
  organisation default at best and a previous request's language at worst.

  So every message is rendered inside `Gettext.with_locale/3` at the
  recipient's stored language, and the locale is restored afterwards: the
  process that asked for the email is not the process the email is for.
  """

  use Gettext, backend: SprintLensWeb.Gettext

  import Swoosh.Email

  alias SprintLens.Accounts
  alias SprintLens.Accounts.User
  alias SprintLens.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"SprintLens", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # A user record built in a test may carry no language at all; the
  # organisation default is the honest answer rather than a crash.
  defp for_recipient(%User{language: language}, fun) do
    language = if is_binary(language), do: language, else: Accounts.default_language()

    Gettext.with_locale(SprintLensWeb.Gettext, language, fun)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    for_recipient(user, fn ->
      deliver(
        user.email,
        gettext("Update email instructions"),
        gettext(
          """

          ==============================

          Hi %{email},

          You can change your email by visiting the URL below:

          %{url}

          If you didn't request this change, please ignore this.

          ==============================
          """,
          email: user.email,
          url: url
        )
      )
    end)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    for_recipient(user, fn ->
      case user do
        %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
        _confirmed -> deliver_magic_link_instructions(user, url)
      end
    end)
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      gettext("Log in instructions"),
      gettext(
        """

        ==============================

        Hi %{email},

        You can log into your account by visiting the URL below:

        %{url}

        If you didn't request this email, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url
      )
    )
  end

  @doc """
  Deliver instructions to reset a forgotten password (FR-004).

  The link signs the user in rather than opening a "choose a new password"
  form directly. A reset link that sets a password without authenticating is a
  standing account-takeover risk if the mailbox is ever compromised later;
  signing in first means the new password is chosen from inside the session.
  """
  def deliver_password_reset_instructions(user, url) do
    for_recipient(user, fn ->
      deliver(
        user.email,
        gettext("Reset your password"),
        gettext(
          """

          ==============================

          Hi %{email},

          Someone asked to reset the password for your SprintLens account.

          Visit the URL below to sign in, then choose a new password in your
          settings:

          %{url}

          This link is valid for a short time. If you didn't ask for it, you can
          ignore this email — your password has not changed.

          ==============================
          """,
          email: user.email,
          url: url
        )
      )
    end)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      gettext("Confirmation instructions"),
      gettext(
        """

        ==============================

        Hi %{email},

        You can confirm your account by visiting the URL below:

        %{url}

        If you didn't create an account with us, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url
      )
    )
  end
end
