defmodule SprintLens.Accounts.UserNotifierTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Accounts.User
  alias SprintLens.Accounts.UserNotifier
  alias SprintLensWeb.Locale

  setup do
    on_exit(fn -> Locale.put(Locale.default()) end)
    :ok
  end

  defp user(attrs \\ %{}) do
    struct(
      %User{
        email: "somchai@example.com",
        language: "th",
        confirmed_at: DateTime.utc_now(:second)
      },
      attrs
    )
  end

  defp thai?(text), do: String.match?(text, ~r/\p{Thai}/u)

  describe "the recipient's language decides, not the sender's" do
    # This is the defect. An email is generated for one person, from a
    # LiveView process or a background job, and neither carries that person's
    # language. Before this, Gettext used whatever the sending process
    # happened to hold.
    @tag req: ["FR-906"]
    test "a Thai user gets a Thai email even when the sender is in English" do
      Locale.put("en")

      {:ok, email} = UserNotifier.deliver_login_instructions(user(), "https://example.test/x")

      assert thai?(email.subject)
      assert thai?(email.text_body)
      assert email.text_body =~ "https://example.test/x"
    end

    @tag req: ["FR-906"]
    test "an English user gets an English email even when the sender is in Thai" do
      Locale.put("th")

      {:ok, email} =
        UserNotifier.deliver_login_instructions(user(%{language: "en"}), "https://example.test/x")

      refute thai?(email.subject)
      refute thai?(email.text_body)
    end

    # `with_locale` rather than `put_locale`: the process that asked for the
    # email is not the process the email is for, and it must get its own
    # locale back.
    @tag req: ["FR-906"]
    test "the sender's own locale survives being borrowed" do
      Locale.put("en")

      {:ok, _email} = UserNotifier.deliver_login_instructions(user(), "https://example.test/x")

      assert Locale.current() == "en"
    end

    @tag req: ["FR-906"]
    test "a record with no language falls back to the organisation default" do
      {:ok, email} =
        UserNotifier.deliver_login_instructions(user(%{language: nil}), "https://example.test/x")

      assert thai?(email.subject)
    end
  end

  describe "every message the product sends" do
    @tag req: ["FR-001"]
    test "an unconfirmed user is asked to confirm rather than simply signed in" do
      {:ok, email} =
        UserNotifier.deliver_login_instructions(
          user(%{confirmed_at: nil}),
          "https://example.test/c"
        )

      assert thai?(email.subject)
      assert email.text_body =~ "https://example.test/c"
    end

    @tag req: ["FR-003"]
    test "changing an email address is explained in the recipient's language" do
      {:ok, email} =
        UserNotifier.deliver_update_email_instructions(user(), "https://example.test/e")

      assert thai?(email.subject)
      assert email.text_body =~ "https://example.test/e"
    end

    @tag req: ["FR-004"]
    test "a password reset is explained in the recipient's language" do
      {:ok, email} =
        UserNotifier.deliver_password_reset_instructions(user(), "https://example.test/r")

      assert thai?(email.subject)
      assert email.text_body =~ "https://example.test/r"
    end
  end
end
