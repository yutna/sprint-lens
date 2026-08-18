defmodule SprintLens.Policy do
  @moduledoc """
  The one implementation of the permission tables in spec sections 3.1 and
  3.2.

  Every surface — LiveView, REST, realtime — authorises through here, so
  NFR-201 ("enforced server side on every request and realtime message") has
  exactly one place to be right or wrong.

  ## Two different things called "access"

  The spec draws a line that is easy to blur:

    * **Management** (section 3.1). An Org Admin may manage members, settings
      and webhooks for *any* team, without belonging to it.
    * **Visibility** (FR-103, section 3.3). Users see only the teams they
      belong to. An Org Admin additionally sees org-wide *aggregates* — never
      another team's board, cards or per-person data (FR-605).

  So `manage?/3` grants an Org Admin rights on a team they are not in, while
  `see_team?/2` does not. Conflating them would hand an Org Admin every
  team's card text, which FR-605 forbids.

  ## Purity

  These functions take the acting user and their role, never a repo. The role
  lookup belongs to `SprintLens.Teams`; deciding what a role may do belongs
  here, and stays exhaustively testable against the spec's tables.
  """

  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Teams.Membership

  @type actor :: User.t() | Scope.t() | nil
  @type role :: Membership.role() | nil
  @type team_action ::
          :create_team
          | :manage_members
          | :edit_team_settings
          | :create_session
          | :view_team_insights
          | :view_org_insights
          | :manage_webhooks
          | :toggle_ai_opt_in
          | :manage_users
          | :purge_data
  @type session_control ::
          :change_phase
          | :control_timer
          | :reveal
          | :set_focus
          | :edit_notes
          | :delete_any_card
          | :transfer_facilitator
          | :close_session

  # Section 3.1, read straight off the table. `:any` means the action needs no
  # team role at all — every signed-in user may do it.
  @team_actions %{
    create_team: :any,
    create_session: :member,
    view_team_insights: :member,
    manage_members: :lead,
    edit_team_settings: :lead,
    manage_webhooks: :lead,
    toggle_ai_opt_in: :lead,
    view_org_insights: :org_admin,
    manage_users: :org_admin,
    purge_data: :org_admin
  }

  # Section 3.2. Everything a facilitator may do, a participant may not.
  @session_controls ~w(
    change_phase control_timer reveal set_focus edit_notes
    delete_any_card transfer_facilitator close_session
  )a

  @doc """
  Every action named in section 3.1.
  """
  @spec team_actions() :: [team_action()]
  def team_actions, do: Map.keys(@team_actions)

  @doc """
  Every control named in section 3.2.
  """
  @spec session_controls() :: [session_control()]
  def session_controls, do: @session_controls

  @doc """
  Whether `actor` may perform a section 3.1 action, given their role in the
  team the action concerns.

  Pass `nil` as the role when the actor does not belong to the team; pass no
  role for org-level actions.
  """
  @spec can?(actor(), team_action(), role()) :: boolean()
  def can?(actor, action, role \\ nil)

  def can?(%Scope{user: user}, action, role), do: can?(user, action, role)
  def can?(nil, _action, _role), do: false
  def can?(%User{is_active: false}, _action, _role), do: false

  def can?(%User{} = user, action, role) do
    case Map.fetch(@team_actions, action) do
      {:ok, :any} -> true
      {:ok, :org_admin} -> user.is_org_admin
      {:ok, :member} -> user.is_org_admin or role in [:lead, :member]
      {:ok, :lead} -> user.is_org_admin or role == :lead
      :error -> false
    end
  end

  @doc """
  Whether `actor` may see a team's contents at all (FR-103, section 3.3).

  Deliberately *not* satisfied by being an Org Admin: org admins get org-wide
  aggregates, not other teams' boards (FR-605).
  """
  @spec see_team?(actor(), role()) :: boolean()
  def see_team?(%Scope{user: user}, role), do: see_team?(user, role)
  def see_team?(nil, _role), do: false
  def see_team?(%User{is_active: false}, _role), do: false
  def see_team?(%User{}, role), do: role in [:lead, :member]

  @doc """
  Whether `actor` may change anything in a team.

  An archived team is read-only (FR-106), so this is false for every actor
  once the team is archived, whatever their role.
  """
  @spec manage?(actor(), team_action(), role(), archived? :: boolean()) :: boolean()
  def manage?(actor, action, role, archived?) do
    not archived? and can?(actor, action, role)
  end

  @doc """
  Whether the given in-session role may use a section 3.2 control.

  Participants may delete their own cards; that is `own_card?` territory, not
  a facilitator control, so `:delete_any_card` is the only deletion listed
  here (FR-301, FR-302).
  """
  @spec session_can?(:facilitator | :participant, session_control()) :: boolean()
  def session_can?(:facilitator, control), do: control in @session_controls
  def session_can?(:participant, _control), do: false

  @doc """
  Whether `user` may edit `card`.

  Only the author. FR-301 gives people the right to edit *their own* cards;
  FR-302 gives the facilitator the right to *delete* any card, which is a
  different thing — removing something from the board is moderation, while
  rewriting it puts words in someone else's mouth.
  """
  @spec edit_card?(User.t() | nil, author_id :: term()) :: boolean()
  def edit_card?(%User{id: id}, author_id) when not is_nil(author_id), do: id == author_id
  def edit_card?(_user, _author_id), do: false

  @doc """
  Whether `user` may delete `card`, which they may if they wrote it or if they
  are facilitating (FR-301, FR-302).
  """
  @spec delete_card?(:facilitator | :participant, User.t() | nil, author_id :: term()) ::
          boolean()
  def delete_card?(:facilitator, _user, _author_id), do: true
  def delete_card?(:participant, %User{id: id}, author_id), do: id == author_id
  def delete_card?(:participant, _user, _author_id), do: false
end
