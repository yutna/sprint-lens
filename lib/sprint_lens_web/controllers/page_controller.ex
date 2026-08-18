defmodule SprintLensWeb.PageController do
  @moduledoc """
  The public landing page.

  Replaced by SCR-02 Home for signed-in users once teams exist; for now it is
  the entry point into registration and sign-in (SCR-01).
  """

  use SprintLensWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
