defmodule SprintLens.AccountsProfileTest do
  @moduledoc """
  The profile, administration and API-token parts of `SprintLens.Accounts`.
  Session and password handling live in `SprintLens.AccountsTest`.
  """

  use SprintLens.DataCase

  import SprintLens.AccountsFixtures

  alias SprintLens.Accounts
  alias SprintLens.Accounts.UserToken

  describe "update_user_profile/2" do
    @tag req: ["FR-003"]
    test "saves the display name, avatar, language and theme" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_user_profile(user, %{
                 display_name: "นก",
                 avatar_url: "https://example.com/nok.png",
                 language: "en",
                 theme: "dark"
               })

      assert updated.display_name == "นก"
      assert updated.avatar_url == "https://example.com/nok.png"
      assert updated.language == "en"
      assert updated.theme == "dark"
    end

    @tag req: ["FR-907", "FR-911"]
    test "the choice persists, so it is there on the next sign-in" do
      user = user_fixture()
      {:ok, _updated} = Accounts.update_user_profile(user, %{language: "en", theme: "dark"})

      reloaded = Accounts.get_user!(user.id)

      assert reloaded.language == "en"
      assert reloaded.theme == "dark"
    end

    @tag req: ["FR-906"]
    test "refuses a language the UI does not have" do
      assert {:error, changeset} = Accounts.update_user_profile(user_fixture(), %{language: "fr"})
      assert %{language: ["is invalid"]} = errors_on(changeset)
    end

    @tag req: ["FR-005"]
    test "cannot be used to grant yourself org-admin rights" do
      user = user_fixture()

      {:ok, updated} = Accounts.update_user_profile(user, %{is_org_admin: true})

      refute updated.is_org_admin
    end
  end

  describe "list_users/0" do
    @tag req: ["FR-801"]
    test "returns every user, newest first" do
      first = user_fixture()
      second = user_fixture()

      ids = Accounts.list_users() |> Enum.map(& &1.id)

      assert first.id in ids
      assert second.id in ids
    end
  end

  describe "deactivate_user/1" do
    @tag req: ["FR-005"]
    test "marks the user inactive" do
      assert {:ok, user} = Accounts.deactivate_user(user_fixture())

      refute user.is_active
    end

    @tag req: ["FR-005", "NFR-206"]
    test "revokes their sessions rather than waiting for them to expire" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert Accounts.get_user_by_session_token(token)

      {:ok, _user} = Accounts.deactivate_user(user)

      refute Accounts.get_user_by_session_token(token)
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end

    @tag req: ["FR-005"]
    test "revokes their API tokens too" do
      user = user_fixture()
      token = Accounts.create_api_token(user)

      assert Accounts.get_user_by_api_token(token)

      {:ok, _user} = Accounts.deactivate_user(user)

      refute Accounts.get_user_by_api_token(token)
    end

    @tag req: ["FR-005"]
    test "a token issued moments before still stops working" do
      user = user_fixture()
      {:ok, deactivated} = Accounts.deactivate_user(user)

      # Simulates a race: a token that reached the database after the purge.
      token = Accounts.generate_user_session_token(deactivated)

      refute Accounts.get_user_by_session_token(token)
    end

    @tag req: ["FR-005"]
    test "keeps their content, which the retention policy governs instead" do
      user = user_fixture()
      {:ok, deactivated} = Accounts.deactivate_user(user)

      assert Accounts.get_user!(deactivated.id).display_name == user.display_name
    end
  end

  describe "activate_user/1" do
    @tag req: ["FR-005"]
    test "restores the ability to sign in" do
      user = deactivated_user_fixture()

      assert {:ok, reactivated} = Accounts.activate_user(user)
      assert reactivated.is_active
    end

    @tag req: ["FR-005"]
    test "does not restore the sessions that were revoked" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      {:ok, deactivated} = Accounts.deactivate_user(user)
      {:ok, _reactivated} = Accounts.activate_user(deactivated)

      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "set_org_admin/2" do
    @tag req: ["FR-801"]
    test "grants and revokes org-admin rights" do
      user = user_fixture()

      assert {:ok, admin} = Accounts.set_org_admin(user, true)
      assert admin.is_org_admin

      assert {:ok, plain} = Accounts.set_org_admin(admin, false)
      refute plain.is_org_admin
    end
  end

  describe "API tokens" do
    @tag req: ["FR-002"]
    test "a freshly issued token resolves to its user" do
      user = user_fixture()

      assert Accounts.get_user_by_api_token(Accounts.create_api_token(user)).id == user.id
    end

    @tag req: ["NFR-205"]
    test "only the hash is stored, so the database never holds a usable token" do
      user = user_fixture()
      token = Accounts.create_api_token(user)

      context = UserToken.api_token_context()

      stored =
        Repo.one!(from t in UserToken, where: t.user_id == ^user.id and t.context == ^context)

      refute stored.token == token
    end

    @tag req: ["NFR-201"]
    test "an unknown token resolves to nobody" do
      refute Accounts.get_user_by_api_token(Base.url_encode64("nope", padding: false))
    end

    @tag req: ["NFR-201"]
    test "a token that is not even base64 resolves to nobody" do
      refute Accounts.get_user_by_api_token("!!! not base64 !!!")
    end

    @tag req: ["NFR-201"]
    test "a non-string is rejected without querying" do
      refute Accounts.get_user_by_api_token(nil)
    end

    @tag req: ["NFR-206"]
    test "revoking clears every API token but leaves the browser session alone" do
      user = user_fixture()
      api_token = Accounts.create_api_token(user)
      session_token = Accounts.generate_user_session_token(user)

      assert Accounts.revoke_api_tokens(user) == 1

      refute Accounts.get_user_by_api_token(api_token)
      assert Accounts.get_user_by_session_token(session_token)
    end
  end

  describe "deliver_password_reset_instructions/2" do
    @tag req: ["FR-004"]
    test "emails a link that signs the user in" do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_password_reset_instructions(user, url)
        end)

      assert Accounts.get_user_by_magic_link_token(token).id == user.id
    end

    # In the recipient's language, which for a new account is the
    # organisation default. The English wording this used to assert was only
    # ever an accident of Gettext having no configured default.
    @tag req: ["FR-004"]
    test "the email explains it is a password reset, not an unexpected login" do
      user = user_fixture()

      {:ok, email} =
        Accounts.deliver_password_reset_instructions(user, fn _token -> "https://example.com" end)

      assert email.subject =~ "รหัสผ่านใหม่"
      assert email.text_body =~ "ตั้งรหัสผ่านใหม่"
    end

    @tag req: ["FR-004", "FR-906"]
    test "and does so in English for someone whose profile says English" do
      {:ok, user} = Accounts.update_user_profile(user_fixture(), %{language: "en"})

      {:ok, email} =
        Accounts.deliver_password_reset_instructions(user, fn _token -> "https://example.com" end)

      assert email.subject =~ "Reset"
      assert email.text_body =~ "reset the password"
    end
  end

  describe "update_user_email/2" do
    @tag req: ["FR-001"]
    test "refuses a token that is not even base64, without querying" do
      assert {:error, :transaction_aborted} =
               Accounts.update_user_email(user_fixture(), "!!! not base64 !!!")
    end

    @tag req: ["FR-001"]
    test "refuses a well-formed token that matches nothing" do
      assert {:error, :transaction_aborted} =
               Accounts.update_user_email(
                 user_fixture(),
                 Base.url_encode64("nope", padding: false)
               )
    end
  end

  describe "session token expiry" do
    @tag req: ["NFR-206"]
    test "the window is configurable at deployment level" do
      assert UserToken.session_validity_in_days() ==
               Application.fetch_env!(:sprint_lens, :session_inactivity_days)
    end

    @tag req: ["NFR-206"]
    test "a token older than the window no longer authenticates" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      days = UserToken.session_validity_in_days()

      offset_user_token(token, -(days + 1), :day)

      refute Accounts.get_user_by_session_token(token)
    end
  end
end
