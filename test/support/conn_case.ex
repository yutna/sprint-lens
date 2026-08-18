defmodule SprintLensWeb.ConnCase do
  @moduledoc """
  Test case for controller, LiveView and channel tests.

  Runs serially for the same reason `SprintLens.DataCase` does — SQLite is
  single-writer and the Ecto sandbox opens deferred transactions, so
  concurrent database access fails rather than waits. See
  `SprintLens.DataCase` for the measurement behind that.
  """

  use ExUnit.CaseTemplate

  using opts do
    if Keyword.get(opts, :async, false) do
      raise ArgumentError, """
      SprintLensWeb.ConnCase cannot run async — see SprintLens.DataCase for why.
      """
    end

    quote do
      # The default endpoint for testing
      @endpoint SprintLensWeb.Endpoint

      use SprintLensWeb, :verified_routes

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import SprintLens.Factory
      import SprintLensWeb.ConnCase
    end
  end

  setup tags do
    SprintLens.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
