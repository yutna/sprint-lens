defmodule SprintLens.DataCase do
  @moduledoc """
  Test case for anything that touches the database.

  ## Why these tests are not `async: true`

  SQLite allows exactly one writer at a time. `Ecto.Adapters.SQL.Sandbox`
  wraps each test in its own transaction on its own connection, and it opens
  that transaction with a plain `BEGIN` (`ecto_sql`'s sandbox hardcodes
  `mode: :transaction`, so this repo's `default_transaction_mode: :immediate`
  does not apply to it). A deferred transaction that later writes has to
  upgrade to a writer, and SQLite refuses to block on that upgrade — it
  returns `SQLITE_BUSY` immediately rather than risk a deadlock, ignoring
  `busy_timeout`.

  The practical result, measured on this project: twenty async test modules
  each doing forty read-then-write cycles produced 95 failures out of 100
  with `Exqlite.Error: Database busy`. The same suite run serially is green.

  So database tests run serially and that is not negotiable — passing
  `async: true` raises rather than silently reintroducing flakiness. Tests
  that need no database use `SprintLens.UnitCase`, which is async and is
  where the bulk of the suite's parallelism comes from.
  """

  use ExUnit.CaseTemplate

  using opts do
    if Keyword.get(opts, :async, false) do
      raise ArgumentError, """
      SprintLens.DataCase cannot run async.

      SQLite is single-writer and the Ecto sandbox opens deferred
      transactions, so concurrent database tests fail with SQLITE_BUSY
      rather than waiting. See the moduledoc for the measurement.

      If this test does not need the database, use SprintLens.UnitCase,
      which is async.
      """
    end

    quote do
      # `Oban.Testing` needs the engine and the notifier as well as the repo:
      # its defaults are the Postgres ones, and this application runs on
      # SQLite, whose notifier is the process-group one.
      use Oban.Testing,
        repo: SprintLens.Repo,
        engine: Oban.Engines.Lite,
        notifier: Oban.Notifiers.PG

      alias SprintLens.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import SprintLens.DataCase
      import SprintLens.Factory
    end
  end

  setup tags do
    SprintLens.DataCase.setup_sandbox(tags)
    SprintLens.DataCase.restore_default_language()
    :ok
  end

  @doc """
  Puts the organisation's cached default language back after the test.

  `SprintLens.Admin.update_settings/2` writes it into the application
  environment so that a change an administrator makes actually takes effect
  (FR-802). The application environment is global, so a test that changes the
  setting would otherwise change the interface language for everything that
  ran after it — including the async modules running beside it.
  """
  def restore_default_language do
    previous = Application.fetch_env(:sprint_lens, :default_language)

    on_exit(fn ->
      case previous do
        {:ok, language} -> Application.put_env(:sprint_lens, :default_language, language)
        :error -> Application.delete_env(:sprint_lens, :default_language)
      end
    end)
  end

  @doc """
  Checks out a sandboxed connection for the test and returns it at the end.

  Always shared, because database tests are always synchronous here: any
  process the test spawns (a `SessionServer`, an Oban worker, a LiveView)
  must see the same connection and therefore the same uncommitted data.
  """
  def setup_sandbox(_tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(SprintLens.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
