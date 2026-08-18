defmodule SprintLensWeb.Api.V1.UserJSONTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Accounts.User
  alias SprintLensWeb.Api.V1.UserJSON

  defp user do
    %User{
      id: 7,
      email: "nok@example.com",
      display_name: "Nok",
      avatar_url: "https://example.com/nok.png",
      language: "th",
      theme: "dark",
      is_org_admin: false,
      is_active: true,
      confirmed_at: ~U[2026-08-18 09:30:00Z]
    }
  end

  describe "profile/1" do
    @tag req: ["FR-003"]
    test "carries the preferences a user manages about themselves" do
      profile = UserJSON.profile(user())

      assert profile.display_name == "Nok"
      assert profile.language == "th"
      assert profile.theme == "dark"
      assert profile.avatar_url == "https://example.com/nok.png"
    end

    @tag req: ["FR-003"]
    test "includes the caller's own email, which is theirs to see" do
      assert UserJSON.profile(user()).email == "nok@example.com"
    end

    @tag req: ["FR-005"]
    test "reports the org-level flags" do
      profile = UserJSON.profile(user())

      assert profile.is_active
      refute profile.is_org_admin
    end

    @tag req: ["NFR-205"]
    test "never carries the password hash" do
      refute Map.has_key?(UserJSON.profile(user()), :hashed_password)
    end
  end

  describe "summary/1" do
    # Data minimisation. NFR-301 (PDPA conformance as a whole) stays a
    # documented gap; this covers one concrete mechanism behind it.
    test "gives teammates a name and an avatar, and no personal data" do
      summary = UserJSON.summary(user())

      assert summary == %{id: 7, display_name: "Nok", avatar_url: "https://example.com/nok.png"}
      refute Map.has_key?(summary, :email)
    end

    @tag req: ["FR-210"]
    test "an absent author serialises as nothing, not as an empty person" do
      assert UserJSON.summary(nil) == nil
    end
  end
end
