defmodule SprintLensWeb.LocaleTest do
  use SprintLens.UnitCase, async: false

  alias SprintLensWeb.Locale

  setup do
    original = Locale.current()
    on_exit(fn -> Locale.put(original) end)
    :ok
  end

  describe "supported/0 and default/0" do
    @tag req: ["FR-906"]
    test "Thai and English, with Thai the default for new users" do
      assert Locale.supported() == ["th", "en"]
      assert Locale.default() == "th"
    end

    @tag req: ["FR-802"]
    test "the default can be changed at organisation level" do
      Application.put_env(:sprint_lens, :default_language, "en")
      on_exit(fn -> Application.delete_env(:sprint_lens, :default_language) end)

      assert Locale.default() == "en"
    end

    @tag req: ["FR-906"]
    test "an unsupported org default falls back to Thai rather than breaking" do
      Application.put_env(:sprint_lens, :default_language, "fr")
      on_exit(fn -> Application.delete_env(:sprint_lens, :default_language) end)

      assert Locale.default() == "th"
    end
  end

  describe "resolve/2" do
    @tag req: ["FR-907"]
    test "the signed-in user's saved choice wins over the browser" do
      assert Locale.resolve(%{language: "en"}, "th") == "en"
    end

    @tag req: ["FR-906"]
    test "falls back to the browser header for a visitor with no account" do
      assert Locale.resolve(nil, "en-GB,en;q=0.9") == "en"
    end

    @tag req: ["FR-906"]
    test "falls back to the org default when nothing else says otherwise" do
      assert Locale.resolve(nil, nil) == "th"
    end

    @tag req: ["FR-906"]
    test "ignores languages the UI does not have" do
      assert Locale.resolve(nil, "fr-FR,de;q=0.8") == "th"
    end

    @tag req: ["FR-906"]
    test "picks the first supported language mentioned by the browser" do
      assert Locale.resolve(nil, "fr-FR,en-US;q=0.9,th;q=0.8") == "en"
    end

    @tag req: ["FR-906"]
    test "a user whose saved language is somehow unsupported falls back" do
      assert Locale.resolve(%{language: "fr"}, "en") == "en"
    end
  end

  describe "put/1 and current/0" do
    @tag req: ["FR-907"]
    test "switching the locale changes what gettext returns" do
      Locale.put("en")
      assert Gettext.gettext(SprintLensWeb.Gettext, "Log in") == "Log in"

      Locale.put("th")
      assert Gettext.gettext(SprintLensWeb.Gettext, "Log in") == "เข้าสู่ระบบ"
    end

    @tag req: ["FR-907"]
    test "reports the active locale" do
      Locale.put("en")
      assert Locale.current() == "en"
    end

    @tag req: ["FR-906"]
    test "an unsupported locale falls back to the default rather than raising" do
      assert Locale.put("fr") == "th"
    end
  end

  describe "supported?/1" do
    @tag req: ["FR-906"]
    test "recognises the two supported languages, in any case" do
      assert Locale.supported?("th")
      assert Locale.supported?("EN")
      assert Locale.supported?(:en)
      refute Locale.supported?("fr")
      refute Locale.supported?(nil)
      refute Locale.supported?(42)
    end
  end

  describe "format_datetime/2" do
    @tag req: ["FR-908"]
    test "renders per the active language's conventions" do
      at = ~U[2026-08-18 09:30:00Z]

      Locale.put("en")
      english = Locale.format_datetime(at)

      Locale.put("th")
      thai = Locale.format_datetime(at)

      assert english != thai
      assert english =~ "2026"
    end

    @tag req: ["FR-908"]
    test "renders in the viewer's time zone while the value stays UTC" do
      at = ~U[2026-08-18 20:30:00Z]

      Locale.put("en")

      assert Locale.format_datetime(at, time_zone: "Asia/Bangkok") !=
               Locale.format_datetime(at, time_zone: "Etc/UTC")
    end
  end

  describe "format_date/2" do
    @tag req: ["FR-908"]
    test "renders a date in the active language" do
      Locale.put("en")
      assert Locale.format_date(~D[2026-08-18]) =~ "2026"
    end
  end

  describe "format_number/2" do
    @tag req: ["FR-908"]
    test "groups digits per the active language" do
      Locale.put("en")
      assert Locale.format_number(1_234_567) == "1,234,567"
    end

    @tag req: ["FR-908"]
    test "formats decimals" do
      Locale.put("en")
      assert Locale.format_number(3.5) == "3.5"
    end
  end
end
