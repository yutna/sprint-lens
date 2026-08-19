defmodule SprintLens.Admin do
  @moduledoc """
  Running the installation: settings, people, retention, erasure and the
  record of all of it (FR-801 to FR-807).

  ## Everything here is audited, in the same transaction

  FR-807 asks for a log of "admin and destructive actions". A purge that
  succeeded and an audit row that did not would leave the organisation unable
  to answer the one question a purge provokes — who did that? — so the two
  happen together or neither does.

  ## Erasure keeps the shape and removes the person

  FR-805 says "erase or anonymize one user's personal data while keeping
  de-identified team aggregates"; section 6.4 says the references on cards,
  votes and mood entries are nullified and the profile is deleted. Deleting
  the row itself would take the audit trail's actor with it and orphan every
  action item the person was assigned. So the row survives as a tombstone with
  nothing personal left in it, which satisfies both readings and keeps
  `participant_count` and every other aggregate honest.

  ## The kill switches mean now

  FR-806 says "immediately disables". A switch that only stopped *new* work
  would leave whatever was already queued to fire afterwards, so
  `webhooks_enabled?/0` is consulted both where a delivery is queued and
  inside the worker that runs it.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias SprintLens.Accounts
  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Admin.AuditEvent
  alias SprintLens.Admin.OrgSettings
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.MoodEntry
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer
  alias SprintLens.Retro.Vote
  alias SprintLens.Teams
  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Team

  ## Settings (FR-802, FR-806)

  @doc """
  The organisation's settings.

  A plain read: the row is seeded by the migration and there is no path that
  removes it.
  """
  @spec settings() :: OrgSettings.t()
  def settings, do: Repo.get!(OrgSettings, OrgSettings.id())

  @doc """
  A changeset for the settings form.
  """
  def change_settings(%OrgSettings{} = settings \\ settings(), attrs \\ %{}) do
    OrgSettings.changeset(settings, attrs)
  end

  @doc """
  Changes the organisation's settings (FR-802, FR-806).
  """
  @spec update_settings(User.t() | Scope.t(), map()) ::
          {:ok, OrgSettings.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_settings(actor, attrs) do
    with :ok <- authorize(actor, :manage_users) do
      current = settings()

      Multi.new()
      |> Multi.update(:settings, OrgSettings.changeset(current, attrs))
      |> audit(actor, "settings.updated", "org_settings:#{current.id}", fn %{settings: updated} ->
        changed(current, updated)
      end)
      |> commit(:settings)
    end
  end

  @doc """
  Whether AI features are switched on (FR-806, AI-003).
  """
  @spec ai_enabled?() :: boolean()
  def ai_enabled?, do: settings().ai_enabled

  @doc """
  Whether webhook deliveries are switched on (FR-806).
  """
  @spec webhooks_enabled?() :: boolean()
  def webhooks_enabled?, do: settings().webhooks_enabled

  ## People (FR-801, FR-005)

  @doc """
  Everybody with an account, by name (FR-801).
  """
  @spec list_users(User.t() | Scope.t()) :: {:ok, [User.t()]} | {:error, :unauthorized}
  def list_users(actor) do
    with :ok <- authorize(actor, :manage_users) do
      {:ok, Repo.all(from u in User, order_by: [asc: u.display_name, asc: u.id])}
    end
  end

  @doc """
  Stops somebody signing in, and revokes the sessions they have open
  (FR-005, FR-801).

  Refused while they are the only lead of a team: FR-801 pairs deactivation
  with reassigning leadership in one sentence, and the reason is this — a team
  whose only lead cannot sign in has nobody who can add a member, change a
  setting or archive it.
  """
  @spec deactivate_user(User.t() | Scope.t(), User.t()) ::
          {:ok, User.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, atom(), map()}
          | {:error, atom()}
  def deactivate_user(actor, %User{} = user) do
    with :ok <- authorize(actor, :manage_users),
         :ok <- not_sole_lead(user) do
      Multi.new()
      |> Multi.run(:user, fn _repo, _changes -> Accounts.deactivate_user(user) end)
      |> audit(actor, "user.deactivated", "user:#{user.id}", fn _changes -> %{} end)
      |> commit(:user)
    end
  end

  @doc """
  Lets somebody sign in again (FR-801).
  """
  @spec reactivate_user(User.t() | Scope.t(), User.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def reactivate_user(actor, %User{} = user) do
    with :ok <- authorize(actor, :manage_users) do
      Multi.new()
      |> Multi.run(:user, fn _repo, _changes -> Accounts.activate_user(user) end)
      |> audit(actor, "user.reactivated", "user:#{user.id}", fn _changes -> %{} end)
      |> commit(:user)
    end
  end

  @doc """
  Makes somebody a lead of a team (FR-801).

  The named reason for this to exist is a team whose lead has left, so it
  works whether or not the person is already a member.
  """
  @spec reassign_leadership(User.t() | Scope.t(), Team.t(), User.t()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def reassign_leadership(actor, %Team{} = team, %User{} = user) do
    with :ok <- authorize(actor, :manage_users) do
      Multi.new()
      |> Multi.insert_or_update(:membership, lead_changeset(team, user))
      |> audit(actor, "team.lead_reassigned", "team:#{team.id}", fn _changes ->
        %{user_id: user.id}
      end)
      |> commit(:membership)
    end
  end

  ## Retention (FR-803, FR-804)

  @doc """
  The closed sessions that are older than the retention period (FR-803).
  """
  @spec expired_sessions(DateTime.t()) :: [Session.t()]
  def expired_sessions(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -settings().retention_days, :day)

    Repo.all(
      from s in Session,
        where: s.state == "closed" and s.closed_at < ^cutoff,
        order_by: [asc: s.closed_at]
    )
  end

  @doc """
  Deletes a session and everything that belongs to it (FR-803, FR-804).

  Section 6.4 lists what goes: columns, cards, groups, votes, mood entries and
  session-scoped AI suggestions. Action items survive with their session link
  cleared — a team's commitments outlive the conversation that produced them,
  which is what the foreign keys were built to do.

  Only a closed session. Purging one that is still running would delete the
  board out from under the people looking at it; "close it first" is the whole
  of the inconvenience.
  """
  @spec purge_session(User.t() | Scope.t() | :system, Session.t()) ::
          {:ok, Session.t()} | {:error, atom()}
  def purge_session(actor, %Session{} = session) do
    with :ok <- authorize(actor, :purge_data),
         :ok <- require_closed(session) do
      # The room is empty by definition — the session is closed — but the
      # process that watched it may still be registered.
      SessionServer.stop(session.id)

      Multi.new()
      |> Multi.delete(:session, session)
      |> audit(actor, "session.purged", "session:#{session.id}", fn _changes ->
        %{team_id: session.team_id, closed_at: session.closed_at}
      end)
      |> commit(:session)
    end
  end

  @doc """
  Deletes a team, its sessions and its history (FR-804).
  """
  @spec purge_team(User.t() | Scope.t(), Team.t()) :: {:ok, Team.t()} | {:error, atom()}
  def purge_team(actor, %Team{} = team) do
    with :ok <- authorize(actor, :purge_data) do
      for session <- Repo.all(from s in Session, where: s.team_id == ^team.id) do
        SessionServer.stop(session.id)
      end

      Multi.new()
      |> Multi.delete(:team, team)
      |> audit(actor, "team.purged", "team:#{team.id}", fn _changes -> %{name: team.name} end)
      |> commit(:team)
    end
  end

  ## PDPA erasure (FR-805, NFR-303)

  @doc """
  Erases one person's personal data, keeping the aggregates built from it
  (FR-805, section 6.4).

  What goes: their authorship of cards, their votes, their mood answers, their
  team memberships, their sign-in tokens, and every personal field on their
  account. What stays: the cards themselves, the counts, the action items they
  were assigned — now unassigned — and the audit trail, because a record of
  what an administrator did is not the erased person's personal data.

  The account row survives as a tombstone rather than being deleted. Deleting
  it would take the audit trail's actor with it if they were ever an
  administrator, and section 6.4's "aggregates built from them remain" needs
  something for the aggregates to have been built from.
  """
  @spec erase_user(User.t() | Scope.t(), User.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def erase_user(actor, %User{} = user) do
    with :ok <- authorize(actor, :manage_users) do
      Multi.new()
      |> Multi.update_all(:cards, from(c in Card, where: c.author_id == ^user.id),
        set: [author_id: nil]
      )
      |> Multi.update_all(:votes, from(v in Vote, where: v.voter_id == ^user.id),
        set: [voter_id: nil]
      )
      |> Multi.update_all(:moods, from(m in MoodEntry, where: m.user_id == ^user.id),
        set: [user_id: nil]
      )
      |> Multi.update_all(:actions, from(a in ActionItem, where: a.assignee_id == ^user.id),
        set: [assignee_id: nil]
      )
      |> Multi.delete_all(:memberships, from(m in Membership, where: m.user_id == ^user.id))
      |> Multi.update(:user, User.erase_changeset(user))
      |> Multi.run(:tokens, fn _repo, _changes -> {:ok, Accounts.revoke_all_tokens(user)} end)
      |> audit(actor, "user.erased", "user:#{user.id}", fn _changes -> %{} end)
      |> commit(:user)
    end
  end

  ## Audit (FR-807)

  @doc """
  The audit log, newest first (FR-807).

  Bounded like the delivery log: somebody reading this page is asking what
  happened recently, and an unbounded query on a page nobody paginates is a
  slow way to make the app feel broken.
  """
  @spec list_audit_events(User.t() | Scope.t(), pos_integer()) ::
          {:ok, [AuditEvent.t()]} | {:error, :unauthorized}
  def list_audit_events(actor, limit \\ 100) do
    with :ok <- authorize(actor, :manage_users) do
      {:ok,
       Repo.all(
         from e in AuditEvent,
           order_by: [desc: e.inserted_at, desc: e.id],
           limit: ^limit,
           preload: [:actor]
       )}
    end
  end

  @doc """
  Records something an administrator did (FR-807).

  Public so a context that is not this one — a webhook being disabled, say —
  can write to the same log rather than starting a second one.
  """
  @spec record_event(User.t() | Scope.t() | :system | nil, String.t(), String.t(), map()) ::
          {:ok, AuditEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_event(actor, action, target, detail \\ %{}) do
    attrs = %{actor_id: actor_id(actor), action: action, target: target}

    # An empty detail is left out rather than stored as `"{}"`: the column is
    # optional and a row that says nothing should look like it.
    attrs = if detail == %{}, do: attrs, else: Map.put(attrs, :detail, detail)

    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end

  ## Internals

  defp audit(multi, actor, action, target, detail_fun) do
    Multi.run(multi, :audit, fn _repo, changes ->
      record_event(actor, action, target, detail_fun.(changes))
    end)
  end

  # Only the two outcomes a caller can do something about. Every step in
  # these transactions either succeeds or fails with a changeset, so anything
  # else means an invariant broke and should be loud.
  defp commit(multi, key) do
    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, Map.fetch!(changes, key)}
      {:error, _step, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  # A purge and a retention sweep are the same operation with a different
  # instigator, so the scheduled one is an actor too — a named one, so the
  # audit log can say the machine did it.
  defp authorize(:system, _action), do: :ok

  # Read afresh rather than trusting the caller's copy. A LiveView's scope is
  # a snapshot taken when the socket connected, so an administrator whose
  # rights were revoked five minutes ago still carries `is_org_admin: true`
  # around in memory. Team roles are already read per call (`Teams.role/2`);
  # this is the one right that was not, and these are the actions where it
  # matters most (NFR-201).
  defp authorize(actor, action) do
    if Policy.can?(current(actor), action), do: :ok, else: {:error, :unauthorized}
  end

  defp current(%Scope{user: user}), do: current(user)
  defp current(%User{id: id}), do: Repo.get(User, id)
  defp current(other), do: other

  defp require_closed(session) do
    if Session.state(session) == :closed, do: :ok, else: {:error, :wrong_state}
  end

  defp not_sole_lead(user) do
    case Teams.sole_lead_teams(user) do
      [] -> :ok
      teams -> {:error, :last_lead, %{team_ids: Enum.map(teams, & &1.id)}}
    end
  end

  defp lead_changeset(team, user) do
    case Repo.get_by(Membership, team_id: team.id, user_id: user.id) do
      nil ->
        Membership.changeset(%Membership{}, %{
          team_id: team.id,
          user_id: user.id,
          role: "lead"
        })

      membership ->
        Membership.changeset(membership, %{role: "lead"})
    end
  end

  # What actually changed, for the audit detail — the whole settings map would
  # say nothing about which switch somebody flipped.
  defp changed(before, later) do
    for key <- [
          :default_language,
          :default_vote_budget,
          :retention_days,
          :ai_enabled,
          :webhooks_enabled
        ],
        Map.get(before, key) != Map.get(later, key),
        into: %{},
        do: {key, Map.get(later, key)}
  end

  defp actor_id(%Scope{user: user}), do: actor_id(user)
  defp actor_id(%User{id: id}), do: id
  defp actor_id(_system_or_nil), do: nil
end
