defmodule SprintLensWeb.ErrorJSONTest do
  use SprintLens.UnitCase, async: true

  alias SprintLensWeb.ErrorJSON

  @tag req: ["FR-919"]
  test "renders 404 in the spec's error envelope" do
    assert %{error: %{code: "not_found", message: message}} = ErrorJSON.render("404.json", %{})
    assert is_binary(message)
  end

  @tag req: ["FR-919"]
  test "renders 500 without leaking technical detail" do
    assert %{error: %{code: "internal_error", message: message}} =
             ErrorJSON.render("500.json", %{})

    refute message =~ "Elixir."
    refute message =~ "stacktrace"
  end

  @tag req: ["NFR-201"]
  test "maps auth failures to their codes" do
    assert %{error: %{code: "unauthenticated"}} = ErrorJSON.render("401.json", %{})
    assert %{error: %{code: "forbidden"}} = ErrorJSON.render("403.json", %{})
  end

  @tag req: ["NFR-202"]
  test "maps a throttled request to the rate limit code" do
    assert %{error: %{code: "rate_limited"}} = ErrorJSON.render("429.json", %{})
  end

  @tag req: ["FR-919"]
  test "maps client errors to their codes" do
    assert %{error: %{code: "validation_failed"}} = ErrorJSON.render("400.json", %{})
    assert %{error: %{code: "validation_failed"}} = ErrorJSON.render("422.json", %{})
    assert %{error: %{code: "conflict"}} = ErrorJSON.render("409.json", %{})
  end

  @tag req: ["NFR-501"]
  test "maps an unavailable dependency to its code" do
    assert %{error: %{code: "dependency_unavailable"}} = ErrorJSON.render("503.json", %{})
  end

  @tag req: ["FR-919"]
  test "falls back to a generic internal error for anything unmapped" do
    assert %{error: %{code: "internal_error"}} = ErrorJSON.render("418.json", %{})
  end
end
