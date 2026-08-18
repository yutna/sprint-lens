defmodule SprintLensWeb.PageControllerTest do
  use SprintLensWeb.ConnCase

  @tag req: ["FR-906"]
  test "GET / renders the landing page in Thai by default", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(lang="th")
    assert html =~ ~p"/users/register"
    assert html =~ ~p"/users/log-in"
  end

  @tag req: ["FR-910"]
  test "GET / offers the theme switcher to signed-out visitors", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(data-phx-theme="dark")
    assert html =~ ~s(data-phx-theme="light")
    assert html =~ ~s(data-phx-theme="system")
  end
end
