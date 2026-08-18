defmodule SprintLens.Retro.SessionServer do
  @moduledoc """
  Time-based orchestration for one live session.

  It exists for a single rule the database cannot express: FR-207 says that if
  the facilitator disconnects for more than sixty seconds, the system must
  offer the role to the remaining participants. "More than sixty seconds" is
  not a query — something has to be waiting.

  ## What it is not

  Not the source of truth. Every fact about the session lives in SQLite
  (NFR-402), and this process reads it when it needs to. If the server dies,
  the session is untouched and a new one starts from the same data. That is
  deliberate: a crash in a countdown must not cost anyone their board.

  ## Why the grace period is configurable

  Sixty real seconds in a test is sixty seconds of a suite nobody will run.
  The period comes from `:facilitator_grace_ms`, which is 50ms under test and
  three seconds in the e2e environment.
  """

  use GenServer, restart: :transient

  require Logger

  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLensWeb.Presence

  @registry SprintLens.Retro.SessionRegistry
  @supervisor SprintLens.Retro.SessionSupervisor

  defstruct [:session_id, :grace_ms, :handover_ref]

  ## Client

  @doc """
  Starts the server for a session, or returns the one already running.

  Idempotent on purpose: every participant's LiveView asks for it on mount,
  and the second one through should get the first one's process.
  """
  @spec ensure_started(term()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(session_id) do
    @supervisor
    |> DynamicSupervisor.start_child({__MODULE__, session_id})
    |> normalise_start()
  end

  @doc """
  Turns a supervisor's start result into `{:ok, pid}`.

  Someone else having started the server first is success, not an error —
  every participant's LiveView asks for it, and only one can be first.
  Anything else is passed through unchanged.
  """
  @spec normalise_start(term()) :: {:ok, pid()} | {:error, term()}
  def normalise_start({:ok, pid}), do: {:ok, pid}
  def normalise_start({:error, {:already_started, pid}}), do: {:ok, pid}
  def normalise_start(other), do: other

  @doc """
  The running server for a session, if there is one.
  """
  @spec whereis(term()) :: pid() | nil
  def whereis(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @doc """
  Tells the server that presence in the session changed.

  Called by the LiveView after it tracks or untracks someone. The server
  decides whether that means the facilitator has gone (start the countdown)
  or come back (cancel it).
  """
  @spec presence_changed(term()) :: :ok
  def presence_changed(session_id) do
    case whereis(session_id) do
      nil -> :ok
      pid -> GenServer.cast(pid, :presence_changed)
    end
  end

  @doc """
  Stops the server for a session. Used when a session closes, and by tests.
  """
  @spec stop(term()) :: :ok
  def stop(session_id) do
    case whereis(session_id) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  @doc """
  Whether a hand-over countdown is currently running. For tests and for the
  board to show "the facilitator has dropped out".
  """
  @spec handover_pending?(term()) :: boolean()
  def handover_pending?(session_id) do
    case whereis(session_id) do
      nil -> false
      pid -> GenServer.call(pid, :handover_pending?)
    end
  end

  def child_spec(session_id) do
    %{
      id: {__MODULE__, session_id},
      start: {__MODULE__, :start_link, [session_id]},
      restart: :transient
    }
  end

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: via(session_id))
  end

  ## Server

  @impl GenServer
  def init(session_id) do
    state = %__MODULE__{
      session_id: session_id,
      grace_ms: Application.get_env(:sprint_lens, :facilitator_grace_ms, 60_000)
    }

    {:ok, state, {:continue, :evaluate}}
  end

  @impl GenServer
  def handle_continue(:evaluate, state), do: {:noreply, evaluate(state)}

  @impl GenServer
  def handle_cast(:presence_changed, state), do: {:noreply, evaluate(state)}

  @impl GenServer
  def handle_call(:handover_pending?, _from, state) do
    {:reply, state.handover_ref != nil, state}
  end

  @impl GenServer
  def handle_info({:handover, ref}, %{handover_ref: ref} = state) do
    {:noreply, hand_over(%{state | handover_ref: nil})}
  end

  # A timer that was cancelled after its message was already in the mailbox.
  def handle_info({:handover, _stale_ref}, state), do: {:noreply, state}

  ## Internals

  # Decides, from who is currently present, whether a hand-over countdown
  # should be running.
  defp evaluate(state) do
    case load(state.session_id) do
      nil ->
        cancel(state)

      session ->
        if facilitator_present?(session) or Session.state(session) != :active do
          cancel(state)
        else
          arm(state)
        end
    end
  end

  defp facilitator_present?(%Session{facilitator_id: nil}), do: false

  defp facilitator_present?(session) do
    Presence.present?(session.id, session.facilitator_id)
  end

  defp arm(%{handover_ref: nil} = state) do
    ref = make_ref()
    Process.send_after(self(), {:handover, ref}, state.grace_ms)

    %{state | handover_ref: ref}
  end

  # Already counting down; restarting the clock every time someone else joins
  # would let a busy session postpone the hand-over indefinitely.
  defp arm(state), do: state

  defp cancel(state), do: %{state | handover_ref: nil}

  defp hand_over(state) do
    with session when not is_nil(session) <- load(state.session_id),
         false <- facilitator_present?(session),
         {:ok, successor} <- pick_successor(session) do
      case Retro.promote_facilitator(session, successor) do
        {:ok, _session} ->
          Logger.info("facilitator handed over", session_id: session.id, user_id: successor)

        {:error, reason} ->
          Logger.warning("facilitator handover failed",
            session_id: session.id,
            reason: inspect(reason)
          )
      end

      state
    else
      _nobody_to_hand_to -> state
    end
  end

  # The longest-present participant, so the role lands on someone who has been
  # in the room rather than whoever refreshed most recently.
  defp pick_successor(session) do
    session.id
    |> Presence.list_users()
    |> Enum.reject(fn {user_id, _meta} -> user_id == session.facilitator_id end)
    |> Enum.min_by(fn {_user_id, meta} -> Map.get(meta, :joined_at, 0) end, fn -> nil end)
    |> case do
      nil -> {:error, :nobody_present}
      {user_id, _meta} -> {:ok, user_id}
    end
  end

  defp load(session_id), do: SprintLens.Repo.get(Session, session_id)

  defp via(session_id), do: {:via, Registry, {@registry, session_id}}
end
