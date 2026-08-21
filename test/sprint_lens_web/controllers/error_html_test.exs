defmodule SprintLensWeb.ErrorHTMLTest do
  use SprintLens.UnitCase, async: true

  # Brings render_to_string/4 for testing views directly.
  import Phoenix.Template, only: [render_to_string: 4]

  alias SprintLensWeb.Locale

  defp render(status), do: render_to_string(SprintLensWeb.ErrorHTML, status, "html", [])

  describe "in English" do
    @describetag locale: "en"

    @tag req: ["FR-919"]
    test "renders 404.html" do
      assert render("404") == "Not Found"
    end

    @tag req: ["FR-919"]
    test "renders 500.html without leaking technical detail" do
      rendered = render("500")

      assert rendered == "Internal Server Error"
      refute rendered =~ "Elixir."
    end
  end

  describe "in the visitor's language" do
    setup do
      on_exit(fn -> Locale.put(Locale.default()) end)
      :ok
    end

    # The defect: Phoenix's generated view reads the phrase out of the
    # template name and never asks Gettext, so a Thai visitor who hit a
    # missing page was told "Not Found".
    @tag req: ["FR-906", "FR-919"]
    test "every status a person can reach is translated" do
      Locale.put("th")

      for status <- ~w(400 401 403 404 422 429 500) do
        rendered = render(status)

        refute rendered =~ ~r/^[\x00-\x7F]+$/,
               "#{status} came back in English: #{rendered}"
      end
    end

    @tag req: ["FR-919"]
    test "a status nobody planned for still says something" do
      Locale.put("th")

      assert render("418") == "I&#39;m a teapot"
    end
  end
end
