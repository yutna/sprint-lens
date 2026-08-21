defmodule SprintLens.Admin.SettingsLoader do
  @moduledoc """
  Reads the organisation's settings into the running system once, at boot.

  Without this, an administrator's change to the default language would hold
  until the next restart and then quietly revert: the value is cached in the
  application environment, and only the update path wrote it there.

  It is a supervised task rather than a call inside `start/2` so that it runs
  after the repository is up. It is skipped in the test environment, where
  the sandbox owns every connection and a boot-time read would either fail or
  pin a value the tests then have to fight.
  """

  use Task, restart: :transient

  alias SprintLens.Admin

  @doc false
  def start_link(_arg), do: Task.start_link(__MODULE__, :run, [])

  @doc """
  Loads the settings, unless this environment has asked not to.
  """
  @spec run() :: :ok
  def run do
    if Application.get_env(:sprint_lens, :load_org_settings, true) do
      Admin.cache_default_language()
    else
      :ok
    end
  end
end
