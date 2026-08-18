defmodule SprintLensWeb.ErrorHTMLTest do
  use SprintLens.UnitCase, async: true

  # Brings render_to_string/4 for testing views directly.
  import Phoenix.Template, only: [render_to_string: 4]

  @tag req: ["FR-919"]
  test "renders 404.html" do
    assert render_to_string(SprintLensWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  @tag req: ["FR-919"]
  test "renders 500.html without leaking technical detail" do
    rendered = render_to_string(SprintLensWeb.ErrorHTML, "500", "html", [])

    assert rendered == "Internal Server Error"
    refute rendered =~ "Elixir."
  end
end
