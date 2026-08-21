defmodule SprintLensWeb.ConnCase do
  @moduledoc """
  Test case for controller, LiveView and channel tests.

  Runs serially for the same reason `SprintLens.DataCase` does — SQLite is
  single-writer and the Ecto sandbox opens deferred transactions, so
  concurrent database access fails rather than waits. See
  `SprintLens.DataCase` for the measurement behind that.
  """

  use ExUnit.CaseTemplate

  # The engine and the notifier follow the configured adapter. Read here, in
  # the module body, because `Application.compile_env!/2` may not be called
  # from inside a function and `use Oban.Testing` expands into one.
  @oban_engine Application.compile_env!(:sprint_lens, :oban_engine)
  @oban_notifier Application.compile_env!(:sprint_lens, :oban_notifier)

  using opts do
    if Keyword.get(opts, :async, false) do
      raise ArgumentError, """
      SprintLensWeb.ConnCase cannot run async — see SprintLens.DataCase for why.
      """
    end

    engine = @oban_engine
    notifier = @oban_notifier

    quote do
      # The default endpoint for testing
      @endpoint SprintLensWeb.Endpoint

      use SprintLensWeb, :verified_routes

      # Same options as `SprintLens.DataCase`: a page that shows what a
      # background job did has to be able to run one (FR-706), and the engine
      # has to be the one the application is configured with rather than a
      # copy that can fall behind it.
      use Oban.Testing,
        repo: SprintLens.Repo,
        engine: unquote(engine),
        notifier: unquote(notifier)

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import SprintLens.Factory
      import SprintLensWeb.ConnCase
    end
  end

  setup tags do
    SprintLens.DataCase.setup_sandbox(tags)
    SprintLens.DataCase.restore_default_language()
    setup_locale(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Pins the organisation default language for a test module.

  The UI is Thai by default (FR-906), so a test that asserts on English copy
  has to say so:

      @moduletag locale: "en"

  Without this, such a test would be asserting on a translation table rather
  than on behaviour, and would break every time a string is translated.
  """
  def setup_locale(%{locale: locale}) do
    previous = Application.get_env(:sprint_lens, :default_language)
    Application.put_env(:sprint_lens, :default_language, locale)
    SprintLensWeb.Locale.put(locale)

    ExUnit.Callbacks.on_exit(fn ->
      if previous do
        Application.put_env(:sprint_lens, :default_language, previous)
      else
        Application.delete_env(:sprint_lens, :default_language)
      end
    end)
  end

  def setup_locale(_tags), do: :ok

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = SprintLens.AccountsFixtures.user_fixture()
    scope = SprintLens.Accounts.Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = SprintLens.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    SprintLens.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
