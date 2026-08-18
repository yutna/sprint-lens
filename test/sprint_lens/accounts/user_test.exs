defmodule SprintLens.Accounts.UserTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Accounts.User

  describe "languages/0 and themes/0" do
    @tag req: ["FR-906"]
    test "the UI is available in Thai and English" do
      assert User.languages() == ["th", "en"]
    end

    @tag req: ["FR-910"]
    test "the theme choices are light, dark and system" do
      assert Enum.sort(User.themes()) == ["dark", "light", "system"]
    end

    @tag req: ["FR-906"]
    test "a new user defaults to Thai" do
      assert %User{}.language == "th"
    end

    @tag req: ["FR-910"]
    test "a new user follows the system theme" do
      assert %User{}.theme == "system"
    end

    @tag req: ["FR-005"]
    test "a new user is active and not an org admin" do
      assert %User{}.is_active
      refute %User{}.is_org_admin
    end
  end

  describe "registration_changeset/3" do
    @tag req: ["FR-003"]
    test "requires a display name alongside the email" do
      changeset =
        User.registration_changeset(%User{}, %{email: "nok@example.com"}, validate_unique: false)

      refute changeset.valid?
      assert %{display_name: ["can't be blank"]} = errors_on(changeset)
    end

    @tag req: ["FR-003"]
    test "accepts an email and a display name" do
      changeset =
        User.registration_changeset(
          %User{},
          %{email: "nok@example.com", display_name: "Nok"},
          validate_unique: false
        )

      assert changeset.valid?
    end

    @tag req: ["FR-001"]
    test "rejects an address without an @ sign" do
      changeset =
        User.registration_changeset(%User{}, %{email: "nope", display_name: "Nok"},
          validate_unique: false
        )

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    @tag req: ["FR-003"]
    test "trims a display name and rejects one that is only whitespace" do
      changeset =
        User.registration_changeset(%User{}, %{email: "a@b.c", display_name: "   "},
          validate_unique: false
        )

      refute changeset.valid?
    end

    @tag req: ["FR-003"]
    test "does not let registration set the org admin flag" do
      changeset =
        User.registration_changeset(
          %User{},
          %{email: "a@b.c", display_name: "Nok", is_org_admin: true},
          validate_unique: false
        )

      refute Ecto.Changeset.get_change(changeset, :is_org_admin)
    end
  end

  describe "profile_changeset/2" do
    @tag req: ["FR-003"]
    test "accepts every profile field" do
      changeset =
        User.profile_changeset(%User{}, %{
          display_name: "Nok",
          avatar_url: "https://example.com/nok.png",
          language: "en",
          theme: "dark"
        })

      assert changeset.valid?
    end

    @tag req: ["FR-003"]
    test "trims the display name" do
      changeset = User.profile_changeset(%User{}, %{display_name: "  Nok  "})

      assert Ecto.Changeset.get_change(changeset, :display_name) == "Nok"
    end

    @tag req: ["FR-906"]
    test "rejects a language the UI does not have" do
      changeset = User.profile_changeset(%User{}, %{display_name: "Nok", language: "fr"})

      assert %{language: ["is invalid"]} = errors_on(changeset)
    end

    @tag req: ["FR-910"]
    test "rejects a theme that is not light, dark or system" do
      changeset = User.profile_changeset(%User{}, %{display_name: "Nok", theme: "neon"})

      assert %{theme: ["is invalid"]} = errors_on(changeset)
    end

    @tag req: ["FR-003"]
    test "rejects an absurdly long avatar url" do
      changeset =
        User.profile_changeset(%User{}, %{
          display_name: "Nok",
          avatar_url: String.duplicate("x", 501)
        })

      refute changeset.valid?
    end

    @tag req: ["FR-005"]
    test "cannot be used to make yourself an org admin or to reactivate yourself" do
      changeset =
        User.profile_changeset(%User{is_active: false}, %{
          display_name: "Nok",
          is_org_admin: true,
          is_active: true
        })

      refute Ecto.Changeset.get_change(changeset, :is_org_admin)
      refute Ecto.Changeset.get_change(changeset, :is_active)
    end
  end

  describe "admin_changeset/2" do
    @tag req: ["FR-005", "FR-801"]
    test "sets the org-level flags" do
      changeset = User.admin_changeset(%User{}, %{is_org_admin: true, is_active: false})

      assert Ecto.Changeset.get_change(changeset, :is_org_admin)
      assert Ecto.Changeset.get_change(changeset, :is_active) == false
    end

    @tag req: ["FR-801"]
    test "ignores profile fields" do
      changeset = User.admin_changeset(%User{}, %{display_name: "Hacked"})

      refute Ecto.Changeset.get_change(changeset, :display_name)
    end
  end

  describe "valid_password?/2" do
    @tag req: ["FR-001"]
    test "is false, and still spends time hashing, when there is no user" do
      refute User.valid_password?(nil, "anything")
    end

    @tag req: ["FR-001"]
    test "is false for an account with no password set" do
      refute User.valid_password?(%User{hashed_password: nil}, "anything")
    end
  end
end
