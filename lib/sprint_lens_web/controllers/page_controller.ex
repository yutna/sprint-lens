defmodule SprintLensWeb.PageController do
  use SprintLensWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
