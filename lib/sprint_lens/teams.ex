defmodule SprintLens.Teams do
  @moduledoc """
  Teams, membership and templates (spec section 4.2, and FR-201/FR-202).

  Every function that changes something takes the acting user first and
  authorises through `SprintLens.Policy`, so the web layer cannot forget to
  (NFR-201). Read functions are scoped to what the caller may see (FR-103).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Team
  alias SprintLens.Teams.Template

  ## Reading

  @doc """
  The teams `user` belongs to, most recently created first (FR-103).

  Org admins are not special here: seeing every team's board is not what
  section 3.3 grants them (FR-605).
  """
  @spec list_teams(User.t() | Scope.t()) :: [Team.t()]
  def list_teams(actor) do
    case user(actor) do
      nil ->
        []

      %User{id: id} ->
        Repo.all(
          from t in Team,
            join: m in Membership,
            on: m.team_id == t.id and m.user_id == ^id,
            order_by: [asc: t.is_archived, desc: t.inserted_at],
            preload: [memberships: ^membership_preload()]
        )
    end
  end

  @doc """
  A team the caller is allowed to see, or `{:error, :not_found}`.

  Returns `:not_found` rather than `:unauthorized` for a team the caller does
  not belong to: telling them it exists is itself a disclosure.
  """
  @spec fetch_team(User.t() | Scope.t(), term()) :: {:ok, Team.t()} | {:error, :not_found}
  def fetch_team(actor, id) do
    with %User{} = user <- user(actor),
         %Team{} = team <- Repo.fetch(Team, id),
         role when not is_nil(role) <- role(user, team) do
      {:ok, Repo.preload(team, memberships: membership_preload())}
    else
      _no_access -> {:error, :not_found}
    end
  end

  @doc """
  A team for an action an Org Admin may take without belonging to it
  (section 3.1), or `{:error, :not_found}`.
  """
  @spec fetch_team_for_management(User.t() | Scope.t(), term()) ::
          {:ok, Team.t()} | {:error, :not_found}
  def fetch_team_for_management(actor, id) do
    with %User{} = user <- user(actor),
         %Team{} = team <- Repo.fetch(Team, id),
         true <- user.is_org_admin or role(user, team) != nil do
      {:ok, Repo.preload(team, memberships: membership_preload())}
    else
      _no_access -> {:error, :not_found}
    end
  end

  @doc """
  `user`'s role in `team`, or `nil` if they do not belong to it.
  """
  @spec role(User.t() | Scope.t() | nil, Team.t() | term()) :: Membership.role() | nil
  def role(actor, team_or_id) do
    with %User{} = user <- user(actor),
         team_id when not is_nil(team_id) <- team_id(team_or_id) do
      Membership
      |> Repo.get_by(user_id: user.id, team_id: team_id)
      |> Membership.role()
    else
      _no_membership -> nil
    end
  end

  @doc """
  The members of a team with their roles, leads first then by name.
  """
  @spec list_members(Team.t()) :: [Membership.t()]
  def list_members(%Team{} = team) do
    Repo.all(
      from m in Membership,
        join: u in assoc(m, :user),
        where: m.team_id == ^team.id,
        order_by: [asc: m.role, asc: u.display_name],
        preload: [user: u]
    )
  end

  ## Writing

  @doc """
  Creates a team, making the creator its Team Lead (FR-101).

  The membership is written in the same transaction as the team: a team with
  no lead would be unmanageable, and nobody could delete it either.
  """
  @spec create_team(User.t() | Scope.t(), map()) ::
          {:ok, Team.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def create_team(actor, attrs) do
    user = user(actor)

    if Policy.can?(user, :create_team) do
      Multi.new()
      |> Multi.insert(:team, Team.create_changeset(%Team{}, attrs))
      |> Multi.insert(:membership, fn %{team: team} ->
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          team_id: team.id,
          role: "lead"
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{team: team}} -> {:ok, Repo.preload(team, memberships: membership_preload())}
        {:error, _step, changeset, _changes} -> {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  A changeset for the create-team form.
  """
  def change_team(%Team{} = team \\ %Team{}, attrs \\ %{}) do
    Team.create_changeset(team, attrs)
  end

  @doc """
  A changeset for the team settings form (FR-105).
  """
  def change_team_settings(%Team{} = team, attrs \\ %{}) do
    Team.settings_changeset(team, attrs)
  end

  @doc """
  Updates the team settings: default template, default vote budget and the AI
  opt-in (FR-105, AI-003).
  """
  @spec update_team_settings(User.t() | Scope.t(), Team.t(), map()) ::
          {:ok, Team.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_team_settings(actor, %Team{} = team, attrs) do
    authorized(actor, team, :edit_team_settings, fn ->
      team
      |> Team.settings_changeset(attrs)
      |> Repo.update()
    end)
  end

  @doc """
  Archives a team, making it read-only while keeping its history (FR-106).
  """
  @spec archive_team(User.t() | Scope.t(), Team.t()) ::
          {:ok, Team.t()} | {:error, :unauthorized}
  def archive_team(actor, %Team{} = team) do
    # Archiving an archived team is not a change worth refusing over, but it
    # must still be a lead's decision, so the archived-team guard is skipped
    # here and only the role is checked.
    if Policy.can?(user(actor), :edit_team_settings, role(actor, team)) do
      team |> Team.archive_changeset(true) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Restores an archived team.
  """
  @spec restore_team(User.t() | Scope.t(), Team.t()) ::
          {:ok, Team.t()} | {:error, :unauthorized}
  def restore_team(actor, %Team{} = team) do
    if Policy.can?(user(actor), :edit_team_settings, role(actor, team)) do
      team |> Team.archive_changeset(false) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Adds a member, or changes an existing member's role (FR-102).

  Section 6.4 says a user has at most one membership per team and that
  changing the role updates that membership, so this upserts rather than
  failing on a duplicate.
  """
  @spec add_member(User.t() | Scope.t(), Team.t(), term(), String.t()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def add_member(actor, %Team{} = team, user_id, role \\ "member") do
    authorized(actor, team, :manage_members, fn ->
      attrs = %{user_id: user_id, team_id: team.id, role: role}

      # Checked here rather than left to the foreign key: SQLite reports a
      # violated foreign key without naming the constraint, so Ecto cannot
      # turn it into a field error, and the caller would get a raise instead
      # of a changeset.
      if Repo.exists?(from u in User, where: u.id == ^user_id) do
        case Repo.get_by(Membership, team_id: team.id, user_id: user_id) do
          nil -> %Membership{} |> Membership.changeset(attrs) |> Repo.insert()
          existing -> existing |> Membership.changeset(attrs) |> Repo.update()
        end
      else
        {:error,
         %Membership{}
         |> Membership.changeset(attrs)
         |> Ecto.Changeset.add_error(:user_id, "does not exist")}
      end
    end)
  end

  @doc """
  Adds a member by email address (FR-102).

  Leads invite people by the address they know, not by an internal id. An
  unknown address is a changeset error on the email field rather than a
  silent no-op, so the form can say what went wrong.
  """
  @spec add_member_by_email(User.t() | Scope.t(), Team.t(), String.t(), String.t()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def add_member_by_email(actor, %Team{} = team, email, role \\ "member") do
    authorized(actor, team, :manage_members, fn ->
      case email |> to_string() |> String.trim() |> User.by_email() |> Repo.one() do
        nil ->
          # Reported on the invite changeset, which has an `email` field, so
          # the form can put the message next to the input the person typed
          # into (FR-919).
          {:error,
           %{email: email, role: role}
           |> Membership.invite_changeset()
           |> Ecto.Changeset.add_error(:email, "no account with that address")}

        %User{} = user ->
          add_member(actor, team, user.id, role)
      end
    end)
  end

  @doc """
  A changeset for the add-member form. Carries no schema field of its own for
  the email, so it is built from a bare map.
  """
  def change_membership(attrs \\ %{}) do
    Membership.invite_changeset(attrs)
  end

  @doc """
  Removes a member (FR-102).

  Refuses to remove the last lead: a team with no lead cannot have its
  membership or settings changed by anyone but an Org Admin.
  """
  @spec remove_member(User.t() | Scope.t(), Team.t(), term()) ::
          :ok | {:error, :unauthorized} | {:error, :last_lead} | {:error, :not_found}
  def remove_member(actor, %Team{} = team, user_id) do
    authorized(actor, team, :manage_members, fn -> do_remove_member(team, user_id) end)
  end

  @doc """
  Lets a member leave a team of their own accord (FR-104).

  Needs no management right — but the last lead still cannot leave, for the
  same reason they cannot be removed.
  """
  @spec leave_team(User.t() | Scope.t(), Team.t()) ::
          :ok | {:error, :last_lead} | {:error, :not_found}
  def leave_team(actor, %Team{} = team) do
    case user(actor) do
      nil -> {:error, :not_found}
      %User{id: id} -> do_remove_member(team, id)
    end
  end

  defp do_remove_member(team, user_id) do
    case Repo.get_by(Membership, team_id: team.id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %Membership{role: "lead"} = membership ->
        if lead_count(team) > 1 do
          Repo.delete!(membership)
          :ok
        else
          {:error, :last_lead}
        end

      membership ->
        Repo.delete!(membership)
        :ok
    end
  end

  @doc """
  The teams where this person is the only lead (FR-801).

  Deactivating or erasing them would leave those teams with nobody who can
  add a member, change a setting or archive them, which is why FR-801 pairs
  deactivation with reassigning leadership in one sentence.
  """
  @spec sole_lead_teams(User.t()) :: [Team.t()]
  def sole_lead_teams(%User{} = user) do
    leads =
      from(m in Membership,
        where: m.role == "lead",
        group_by: m.team_id,
        having: count(m.id) == 1,
        select: m.team_id
      )

    Repo.all(
      from t in Team,
        join: m in Membership,
        on: m.team_id == t.id,
        where: m.user_id == ^user.id and m.role == "lead",
        where: t.id in subquery(leads),
        order_by: [asc: t.name]
    )
  end

  defp lead_count(team) do
    Repo.aggregate(
      from(m in Membership, where: m.team_id == ^team.id and m.role == "lead"),
      :count
    )
  end

  ## Templates

  @doc """
  The templates a team may start a session from: the built-ins plus its own
  (FR-201, FR-202).
  """
  @spec list_templates(Team.t()) :: [Template.t()]
  def list_templates(%Team{} = team) do
    Repo.all(
      from t in Template,
        where: t.is_builtin or t.team_id == ^team.id,
        order_by: [desc: t.is_builtin, asc: t.name]
    )
  end

  @doc """
  Only the built-in templates (FR-201).
  """
  @spec list_builtin_templates() :: [Template.t()]
  def list_builtin_templates do
    Repo.all(from t in Template, where: t.is_builtin, order_by: [asc: t.name])
  end

  @doc """
  A template the caller's team may use, or `{:error, :not_found}`.
  """
  @spec fetch_template(Team.t(), term()) :: {:ok, Template.t()} | {:error, :not_found}
  def fetch_template(%Team{} = team, id) do
    case Repo.fetch(Template, id) do
      %Template{is_builtin: true} = template -> {:ok, template}
      %Template{team_id: team_id} = template when team_id == team.id -> {:ok, template}
      _other -> {:error, :not_found}
    end
  end

  @doc """
  A changeset for the template form.
  """
  def change_template(%Template{} = template \\ %Template{}, attrs \\ %{}) do
    Template.changeset(template, attrs)
  end

  @doc """
  Saves a custom template for a team to reuse (FR-202).
  """
  @spec create_template(User.t() | Scope.t(), Team.t(), map()) ::
          {:ok, Template.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def create_template(actor, %Team{} = team, attrs) do
    authorized(actor, team, :create_session, fn ->
      %Template{team_id: team.id}
      |> Template.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc """
  Updates one of a team's own templates. Built-ins are not editable.
  """
  @spec update_template(User.t() | Scope.t(), Team.t(), Template.t(), map()) ::
          {:ok, Template.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized}
          | {:error, :builtin}
  def update_template(actor, %Team{} = team, %Template{} = template, attrs) do
    authorized(actor, team, :create_session, fn ->
      if template.is_builtin do
        {:error, :builtin}
      else
        template |> Template.changeset(attrs) |> Repo.update()
      end
    end)
  end

  @doc """
  Deletes one of a team's own templates. Built-ins are not deletable.
  """
  @spec delete_template(User.t() | Scope.t(), Team.t(), Template.t()) ::
          :ok | {:error, :unauthorized} | {:error, :builtin}
  def delete_template(actor, %Team{} = team, %Template{} = template) do
    authorized(actor, team, :create_session, fn ->
      if template.is_builtin do
        {:error, :builtin}
      else
        Repo.delete!(template)
        :ok
      end
    end)
  end

  ## Helpers

  # Every write goes through here: the role is looked up once, the archived
  # guard is applied once, and the caller cannot forget either.
  defp authorized(actor, team, action, fun) do
    if Policy.manage?(user(actor), action, role(actor, team), team.is_archived) do
      fun.()
    else
      {:error, :unauthorized}
    end
  end

  defp membership_preload, do: from(m in Membership, preload: [:user])

  defp user(%Scope{user: user}), do: user
  defp user(%User{} = user), do: user
  defp user(_other), do: nil

  defp team_id(%Team{id: id}), do: id
  defp team_id(id) when is_integer(id), do: id
  defp team_id(id) when is_binary(id), do: id
  defp team_id(_other), do: nil
end
