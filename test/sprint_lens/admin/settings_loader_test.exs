defmodule SprintLens.Admin.SettingsLoaderTest do
  use SprintLens.DataCase

  import SprintLens.AccountsFixtures

  alias SprintLens.Accounts
  alias SprintLens.Admin
  alias SprintLens.Admin.SettingsLoader

  setup do
    Application.delete_env(:sprint_lens, :default_language)
    :ok
  end

  describe "run/0" do
    @tag req: ["FR-802"]
    test "lifts the organisation's default language into the running system" do
      Application.put_env(:sprint_lens, :load_org_settings, true)
      on_exit(fn -> Application.put_env(:sprint_lens, :load_org_settings, false) end)

      {:ok, _settings} = Admin.update_settings(org_admin_fixture(), %{default_language: "en"})
      # As if the node had just restarted: the row says English, the cache is
      # empty, and the loader is what closes the gap.
      Application.delete_env(:sprint_lens, :default_language)

      assert SettingsLoader.run() == :ok
      assert Accounts.default_language() == "en"
    end

    # The test environment pins the language per module and the sandbox owns
    # every connection at boot, so a read here would fight both.
    @tag req: ["FR-802"]
    test "does nothing when the environment has asked it not to" do
      Application.put_env(:sprint_lens, :load_org_settings, false)
      on_exit(fn -> Application.put_env(:sprint_lens, :load_org_settings, false) end)

      assert SettingsLoader.run() == :ok
      assert Application.fetch_env(:sprint_lens, :default_language) == :error
    end
  end

  describe "the setting an administrator changes" do
    # It was editable, it was audited, and no code ever read it. An
    # administrator could switch the organisation to English and watch the
    # interface stay in Thai, which left FR-802 half built.
    @tag req: ["FR-802"]
    test "takes effect without waiting for a restart" do
      admin = org_admin_fixture()

      assert Accounts.default_language() == "th"

      {:ok, _settings} = Admin.update_settings(admin, %{default_language: "en"})

      assert Accounts.default_language() == "en"
    end

    @tag req: ["FR-802"]
    test "and a rejected change leaves the running system alone" do
      admin = org_admin_fixture()
      {:ok, _settings} = Admin.update_settings(admin, %{default_language: "en"})

      assert {:error, _changeset} = Admin.update_settings(admin, %{default_language: "fr"})
      assert Accounts.default_language() == "en"
    end

    @tag req: ["FR-802"]
    test "and someone without the permission changes nothing at all" do
      assert {:error, :unauthorized} =
               Admin.update_settings(user_fixture(), %{default_language: "en"})

      assert Application.fetch_env(:sprint_lens, :default_language) == :error
    end
  end

  describe "cache_default_language/0" do
    @tag req: ["FR-802"]
    test "reads the stored row rather than guessing" do
      assert Admin.cache_default_language() == :ok
      assert Accounts.default_language() == "th"
    end
  end
end
