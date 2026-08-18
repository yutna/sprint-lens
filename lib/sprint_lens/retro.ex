defmodule SprintLens.Retro do
  @moduledoc """
  Retrospective sessions: creating them, joining them, and moving them through
  their lifecycle and phases (spec section 4.3).

  Every function that changes something takes the acting user first and
  authorises through `SprintLens.Policy`, then broadcasts the section 7.3
  event for the change. The web layer never broadcasts and never decides
  permissions — that way the LiveView, the REST API and any realtime intent
  all go through the same gate (NFR-201).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLens.Teams.Team
  alias SprintLens.Teams.Template

  @preloads [:team, :facilitator, :columns]

  ## Reading

  @doc """
  A team's sessions, upcoming first then most recent (FR-203).
  """
  @spec list_sessions(Team.t()) :: [Session.t()]
  def list_sessions(%Team{} = team) do
    Repo.all(
      from s in Session,
        where: s.team_id == ^team.id,
        order_by: [asc: s.closed_at, desc: s.inserted_at],
        preload: ^@preloads
    )
  end

  @doc """
  A team's sessions that are still open — scheduled or running (FR-203).
  """
  @spec list_open_sessions(Team.t()) :: [Session.t()]
  def list_open_sessions(%Team{} = team) do
    Repo.all(
      from s in Session,
        where: s.team_id == ^team.id and s.state != "closed",
        order_by: [asc: s.scheduled_at, desc: s.inserted_at],
        preload: ^@preloads
    )
  end

  @doc """
  A session the caller may see, or `{:error, :not_found}`.

  Membership of the session's team is what grants access (FR-103, FR-204);
  an Org Admin does not get another team's board (FR-605).
  """
  @spec fetch_session(User.t() | Scope.t(), term()) ::
          {:ok, Session.t()} | {:error, :not_found}
  def fetch_session(actor, id) do
    with %Session{} = session <- Repo.fetch(Session, id) |> preload(),
         true <- Policy.see_team?(actor, Teams.role(actor, session.team_id)) do
      {:ok, session}
    else
      _no_access -> {:error, :not_found}
    end
  end

  @doc """
  Finds an active session by its join code (FR-204).

  Only a signed-in member of the session's team can join, so the same
  `:not_found` is returned for a wrong code and for a code belonging to
  someone else's team — a join form should not double as a way to discover
  which codes exist.
  """
  @spec fetch_session_by_code(User.t() | Scope.t(), String.t()) ::
          {:ok, Session.t()} | {:error, :not_found} | {:error, :session_closed}
  def fetch_session_by_code(actor, code) do
    normalised = Session.normalise_join_code(code)

    with false <- normalised == "",
         %Session{} = session <- Repo.get_by(Session, join_code: normalised) |> preload(),
         true <- Policy.see_team?(actor, Teams.role(actor, session.team_id)) do
      if Session.state(session) == :closed, do: {:error, :session_closed}, else: {:ok, session}
    else
      _no_access -> {:error, :not_found}
    end
  end

  @doc """
  How many sessions of a team are currently active.
  """
  @spec count_active_sessions(Team.t()) :: non_neg_integer()
  def count_active_sessions(%Team{} = team) do
    Repo.aggregate(
      from(s in Session, where: s.team_id == ^team.id and s.state == "active"),
      :count
    )
  end

  ## Creating

  @doc """
  A changeset for the create-session form.
  """
  def change_session(%Session{} = session \\ %Session{}, attrs \\ %{}) do
    Session.create_changeset(session, attrs)
  end

  @doc """
  Creates a session from a template (FR-201, FR-202, FR-203).

  The template's columns are copied onto the session in the same transaction.
  Copying rather than referencing means a team editing a template later does
  not rewrite the headings of a retrospective that already happened, which is
  what makes the recap in FR-602 truthful.

  The creator facilitates by default (FR-207), and the team's own defaults
  fill in the vote budget and template when the caller does not choose
  (FR-105).
  """
  @spec create_session(User.t() | Scope.t(), Team.t(), map()) ::
          {:ok, Session.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized}
          | {:error, :not_found}
  def create_session(actor, %Team{} = team, attrs) do
    user = user(actor)

    if Policy.manage?(user, :create_session, Teams.role(user, team), team.is_archived) do
      insert_session(user, team, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp insert_session(user, team, attrs) do
    attrs = defaults(team, user, attrs)

    with {:ok, columns} <- template_columns(team, attrs[:template_id] || attrs["template_id"]) do
      Multi.new()
      |> Multi.insert(:session, Session.create_changeset(%Session{}, attrs))
      |> Multi.insert_all(:columns, Column, &column_rows(columns, &1.session))
      |> Repo.transaction()
      |> case do
        {:ok, %{session: session}} -> {:ok, preload(session)}
        {:error, _step, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  # `insert_all` takes plain maps rather than changesets, so the timestamps
  # `timestamps()` would normally fill in have to be supplied here.
  defp column_rows(columns, session) do
    now = DateTime.utc_now(:second)

    Enum.map(
      columns,
      &Map.merge(&1, %{session_id: session.id, inserted_at: now, updated_at: now})
    )
  end

  # The form sends strings; internal callers send atoms. Normalising once here
  # keeps every default in one place instead of scattered across both shapes.
  defp defaults(team, user, attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("team_id", team.id)
    |> Map.put("facilitator_id", user.id)
    |> Map.put_new("title", default_title())
    |> put_default("template_id", team.default_template_id)
    |> put_default("vote_budget", team.default_vote_budget)
  end

  defp put_default(attrs, key, value) do
    case Map.get(attrs, key) do
      nil -> Map.put(attrs, key, value)
      "" -> Map.put(attrs, key, value)
      _present -> attrs
    end
  end

  defp default_title do
    "Retrospective #{Date.utc_today() |> Date.to_iso8601()}"
  end

  # A session with no template still gets a board: an empty one would leave
  # participants with nowhere to write (FR-917).
  @fallback_columns [
    %{"name" => "Went well", "hint" => nil},
    %{"name" => "To improve", "hint" => nil},
    %{"name" => "Actions", "hint" => nil}
  ]

  defp template_columns(_team, nil), do: {:ok, Column.attrs_from_template(@fallback_columns)}

  defp template_columns(team, template_id) do
    case Teams.fetch_template(team, template_id) do
      {:ok, %Template{columns: columns}} -> {:ok, Column.attrs_from_template(columns)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  ## Lifecycle (FR-205)

  @doc """
  Starts a session, moving it from `created` to `active` (FR-205).
  """
  @spec start_session(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, :wrong_state}
  def start_session(actor, %Session{} = session) do
    with :ok <- authorize_facilitator(actor, session, :change_phase),
         :ok <- require_state(session, :created) do
      session
      |> Session.state_changeset("active")
      |> Repo.update()
      |> broadcast_result("phase.changed", &phase_payload/1)
    end
  end

  @doc """
  Closes a session (FR-205, FR-215).

  A closed session is read-only except for its action items (FR-503), and
  closing is what triggers the recap.
  """
  @spec close_session(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, :wrong_state}
  def close_session(actor, %Session{} = session) do
    with :ok <- authorize_facilitator(actor, session, :close_session),
         :ok <- require_state(session, :active) do
      # Closing is the moment an anonymous session's authorship is destroyed
      # (FR-210, NFR-304). Done in the same transaction as the state change so
      # a session cannot end up closed with its authorship intact.
      #
      # Both reveals go up here too. FR-602 requires the recap to show the
      # cards and the vote totals, and a session that ended before the
      # facilitator revealed them would otherwise have a recap that either
      # withholds them forever or leaks them without anyone deciding to.
      Multi.new()
      |> Multi.update(:session, Session.state_changeset(session, "closed"))
      |> Multi.update(:reveal, fn %{session: closed} ->
        Session.reveal_changeset(closed, %{cards_revealed: true, votes_revealed: true})
      end)
      |> Multi.run(:strip, fn _repo, %{reveal: closed} ->
        {SprintLens.Retro.Board.strip_authorship(closed), nil}
      end)
      |> Repo.transaction()
      # Matched rather than cased: neither step can fail. The state change is
      # a bare `change/2` and the strip is an `update_all`. A failure here
      # would mean an invariant broke, and should be loud rather than turned
      # into a changeset nobody expects.
      |> then(fn {:ok, %{reveal: closed}} ->
        broadcast_result({:ok, closed}, "session.closed", fn c ->
          %{session_id: c.id, closed_at: c.closed_at}
        end)
      end)
    end
  end

  ## Phases (FR-206)

  @doc """
  Moves to the next phase.
  """
  @spec advance_phase(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, :wrong_phase}
  def advance_phase(actor, %Session{} = session) do
    set_phase(actor, session, Session.next_phase(session))
  end

  @doc """
  Moves back to the previous phase (FR-206).
  """
  @spec revert_phase(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, :wrong_phase}
  def revert_phase(actor, %Session{} = session) do
    set_phase(actor, session, Session.previous_phase(session))
  end

  @doc """
  Moves to any phase, which is how a phase is skipped (FR-206).

  Skipping and reverting are the same operation with a different target, so
  they share one authorisation and one broadcast.
  """
  @spec set_phase(User.t() | Scope.t(), Session.t(), Session.phase() | nil) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, :wrong_phase}
  def set_phase(_actor, _session, nil), do: {:error, :wrong_phase}

  def set_phase(actor, %Session{} = session, phase) do
    with :ok <- authorize_facilitator(actor, session, :change_phase),
         :ok <- require_state(session, :active),
         true <- phase in Session.phases() do
      session
      |> Session.phase_changeset(Atom.to_string(phase))
      |> Repo.update()
      |> broadcast_result("phase.changed", &phase_payload/1)
    else
      false -> {:error, :wrong_phase}
      {:error, :wrong_state} -> {:error, :wrong_phase}
      error -> error
    end
  end

  ## Timer (FR-208)

  @doc """
  Starts a countdown of `duration_s` seconds, or resumes a paused one.
  """
  @spec start_timer(User.t() | Scope.t(), Session.t(), pos_integer() | nil) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def start_timer(actor, %Session{} = session, duration_s \\ nil) do
    with :ok <- authorize_facilitator(actor, session, :control_timer) do
      duration = duration_s || session.timer_remaining_s || session.timer_duration_s

      session
      |> Session.timer_changeset(%{
        timer_duration_s: duration,
        timer_started_at: DateTime.utc_now(),
        timer_remaining_s: nil
      })
      |> Repo.update()
      |> broadcast_result("timer.updated", &timer_payload/1)
    end
  end

  @doc """
  Pauses the timer, keeping what is left of it (FR-208).
  """
  @spec pause_timer(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def pause_timer(actor, %Session{} = session) do
    with :ok <- authorize_facilitator(actor, session, :control_timer) do
      session
      |> Session.timer_changeset(%{
        timer_remaining_s: Session.timer_remaining(session),
        timer_started_at: nil
      })
      |> Repo.update()
      |> broadcast_result("timer.updated", &timer_payload/1)
    end
  end

  @doc """
  Clears the timer entirely (FR-208).
  """
  @spec reset_timer(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def reset_timer(actor, %Session{} = session) do
    with :ok <- authorize_facilitator(actor, session, :control_timer) do
      session
      |> Session.timer_changeset(%{
        timer_duration_s: nil,
        timer_started_at: nil,
        timer_remaining_s: nil
      })
      |> Repo.update()
      |> broadcast_result("timer.updated", &timer_payload/1)
    end
  end

  ## Facilitator (FR-207)

  @doc """
  Hands the facilitator role to another participant (FR-207).

  The new facilitator has to be a member of the team: handing the role to
  someone who cannot even see the board would leave the session with no one
  able to advance it.
  """
  @spec transfer_facilitator(User.t() | Scope.t(), Session.t(), term()) ::
          {:ok, Session.t()} | {:error, :unauthorized} | {:error, :not_found}
  def transfer_facilitator(actor, %Session{} = session, user_id) do
    with :ok <- authorize_facilitator(actor, session, :transfer_facilitator),
         %User{} = target <- Repo.get(User, user_id),
         true <- Policy.see_team?(target, Teams.role(target, session.team_id)) do
      session
      |> Session.facilitator_changeset(target.id)
      |> Repo.update()
      |> broadcast_result("presence.updated", fn updated ->
        %{session_id: updated.id, facilitator_id: updated.facilitator_id}
      end)
    else
      {:error, reason} -> {:error, reason}
      _not_a_member -> {:error, :not_found}
    end
  end

  @doc """
  Hands the role over without an acting facilitator, which is what happens
  when the facilitator has been gone for longer than the grace period
  (FR-207).

  Called only by `SprintLens.Retro.SessionServer`; it deliberately takes no
  actor, because there is nobody to authorise — the point is that the session
  is not left stranded.
  """
  @spec promote_facilitator(Session.t(), term()) :: {:ok, Session.t()} | {:error, :not_found}
  def promote_facilitator(%Session{} = session, user_id) do
    with %User{} = target <- Repo.get(User, user_id),
         true <- Policy.see_team?(target, Teams.role(target, session.team_id)) do
      session
      |> Session.facilitator_changeset(target.id)
      |> Repo.update()
      |> broadcast_result("presence.updated", fn updated ->
        %{session_id: updated.id, facilitator_id: updated.facilitator_id, reason: "handover"}
      end)
    else
      _not_a_member -> {:error, :not_found}
    end
  end

  @doc """
  Whether `actor` is facilitating this session (section 3.2).
  """
  @spec facilitator?(User.t() | Scope.t() | nil, Session.t()) :: boolean()
  def facilitator?(actor, %Session{} = session) do
    case user(actor) do
      %User{id: id} -> id == session.facilitator_id
      nil -> false
    end
  end

  @doc """
  The in-session role of `actor`, which is what `SprintLens.Policy` reasons
  about (section 3.2).
  """
  @spec session_role(User.t() | Scope.t() | nil, Session.t()) :: :facilitator | :participant
  def session_role(actor, %Session{} = session) do
    if facilitator?(actor, session), do: :facilitator, else: :participant
  end

  ## Snapshot (FR-309)

  @doc """
  Everything a client needs to render the board from scratch.

  Sent on connect and on reconnect, before any incremental event, so a client
  that missed messages while disconnected does not have to guess what it
  missed (FR-309, NFR-401).
  """
  @spec snapshot(Session.t(), DateTime.t()) :: map()
  def snapshot(%Session{} = session, now \\ DateTime.utc_now()) do
    %{
      session_id: session.id,
      state: Session.state(session),
      phase: Session.phase(session),
      is_anonymous: session.is_anonymous,
      is_blind: session.is_blind,
      cards_revealed: session.cards_revealed,
      votes_revealed: session.votes_revealed,
      vote_budget: session.vote_budget,
      multi_vote: session.multi_vote,
      facilitator_id: session.facilitator_id,
      timer: timer_payload(session, now),
      columns:
        Enum.map(session.columns, fn column ->
          %{id: column.id, name: column.name, hint: column.hint, position: column.position}
        end)
    }
  end

  ## Helpers

  @doc false
  @spec preload(Session.t() | nil) :: Session.t() | nil
  def preload(nil), do: nil
  def preload(%Session{} = session), do: Repo.preload(session, @preloads)

  defp authorize_facilitator(actor, session, control) do
    cond do
      not Policy.see_team?(actor, Teams.role(actor, session.team_id)) -> {:error, :unauthorized}
      not Policy.session_can?(session_role(actor, session), control) -> {:error, :unauthorized}
      true -> :ok
    end
  end

  defp require_state(session, expected) do
    if Session.state(session) == expected, do: :ok, else: {:error, :wrong_state}
  end

  defp broadcast_result({:ok, session}, event, payload_fun) do
    session = preload(session)
    Events.broadcast(session.id, event, payload_fun.(session))

    {:ok, session}
  end

  defp broadcast_result(error, _event, _payload_fun), do: error

  defp phase_payload(session) do
    %{
      session_id: session.id,
      state: Session.state(session),
      phase: Session.phase(session),
      timer: timer_payload(session)
    }
  end

  defp timer_payload(session, now \\ DateTime.utc_now()) do
    %{
      duration_s: session.timer_duration_s,
      remaining_s: Session.timer_remaining(session, now),
      running: Session.timer_running?(session)
    }
  end

  defp user(%Scope{user: user}), do: user
  defp user(%User{} = user), do: user
  defp user(_other), do: nil
end
