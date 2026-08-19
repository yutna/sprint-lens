defmodule SprintLens.Actions do
  @moduledoc """
  Action items: what the team agreed to do, and what happened to it (FR-501 to
  FR-506).

  ## One rule about "open" that everything else depends on

  FR-505 lets an item still open at the next check-in be carried into that
  session as a new item linking back to the old one. If both then counted as
  open, the team would see the same commitment twice — once as the thing they
  agreed last sprint and once as the thing they agreed this sprint — and
  FR-506's completion rate would be measured against a list that grows every
  time nothing gets done.

  So `open_query/1` excludes an item that something newer was carried from.
  The original's status is untouched: it was never dropped and it was never
  done, it was superseded. The check-in review, the Home page and the insights
  all read through that one query.

  The full list of FR-504 does *not* exclude anything. That view is the team's
  history, and a superseded item there is a fact about what happened, shown
  with the link to what replaced it.

  ## Who may do what

  Membership, and nothing finer. FR-503 says team members update items "at any
  time, including after the session closes", so there is no facilitator right
  here and no session state to check on update — only on creation, which
  belongs to a live session's discuss or wrap-up phase (FR-501).
  """

  import Ecto.Query, warn: false

  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic
  alias SprintLens.Teams
  alias SprintLens.Teams.Team

  @preloads [:assignee, :session, :carried_from]

  # FR-501 names the two phases an action can be written in. Carrying over is
  # its own thing and happens at check-in (FR-505).
  @create_phases [:discuss, :wrapup]
  @carry_phases [:checkin]

  ## Reading

  @doc """
  Every action item a team owns, newest first (FR-504).

  `filters` accepts `:status`, `:assignee_id` and `:session_id`, which are the
  three FR-504 names. Nothing is excluded here — a superseded item is part of
  the team's history and appears with the link to what replaced it.
  """
  @spec list_actions(Team.t(), keyword() | map()) :: [ActionItem.t()]
  def list_actions(%Team{} = team, filters \\ []) do
    team
    |> team_query()
    |> apply_filters(filters)
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc """
  The team's items that still ask something of somebody (FR-505).

  Excludes anything a newer item was carried from — see the module doc.
  """
  @spec list_open_actions(Team.t()) :: [ActionItem.t()]
  def list_open_actions(%Team{} = team) do
    team
    |> open_query()
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc """
  The open items assigned to one person, across every team they belong to
  (SCR-02).
  """
  @spec list_my_actions(User.t() | Scope.t() | nil) :: [ActionItem.t()]
  def list_my_actions(actor) do
    case user(actor) do
      nil ->
        []

      user ->
        team_ids = Enum.map(Teams.list_teams(user), & &1.id)

        team_ids
        |> open_query()
        |> where([a], a.assignee_id == ^user.id)
        |> order_by([a], asc: a.due_date, asc: a.inserted_at)
        |> preload(^@preloads)
        |> Repo.all()
    end
  end

  @doc """
  The items produced by one session, oldest first (FR-602).
  """
  @spec list_session_actions(Session.t()) :: [ActionItem.t()]
  def list_session_actions(%Session{} = session) do
    Repo.all(
      from a in ActionItem,
        where: a.session_id == ^session.id,
        order_by: [asc: a.inserted_at, asc: a.id],
        preload: ^@preloads
    )
  end

  @doc """
  An action item the caller's membership lets them see, or `{:error,
  :not_found}`.
  """
  @spec fetch_action(User.t() | Scope.t() | nil, term()) ::
          {:ok, ActionItem.t()} | {:error, :not_found}
  def fetch_action(actor, id) do
    with %ActionItem{} = item <- Repo.fetch(ActionItem, id),
         true <- Policy.see_team?(actor, Teams.role(actor, item.team_id)) do
      {:ok, Repo.preload(item, @preloads)}
    else
      _no_access -> {:error, :not_found}
    end
  end

  @doc """
  The query behind every "still open" list (FR-505, FR-506).

  Takes a team or a list of team ids. Superseded items — the ones a carried
  copy points back to — are excluded, because the copy is now the live record
  of the same commitment.
  """
  @spec open_query(Team.t() | [term()]) :: Ecto.Query.t()
  def open_query(%Team{} = team), do: open_query([team.id])

  def open_query(team_ids) when is_list(team_ids) do
    superseded =
      from a in ActionItem, where: not is_nil(a.carried_from_id), select: a.carried_from_id

    from a in ActionItem,
      where: a.team_id in ^team_ids,
      where: a.status in ^live_status_names(),
      where: a.id not in subquery(superseded)
  end

  @doc """
  A changeset for the action item form.
  """
  def change_action(%ActionItem{} = item \\ %ActionItem{}, attrs \\ %{}) do
    ActionItem.create_changeset(item, attrs)
  end

  ## Writing

  @doc """
  Writes down something the team agreed to do (FR-501, FR-502).

  Only during discuss and wrap-up, and only in a live session: an action is
  the outcome of a conversation, and there is no conversation to be the
  outcome of before the board has been read.
  """
  @spec create_action(User.t() | Scope.t(), Session.t(), map()) ::
          {:ok, ActionItem.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized | :session_closed | :wrong_phase | :not_found}
  def create_action(actor, %Session{} = session, attrs) do
    attrs = attrs |> stringify() |> normalise_due_date()

    with :ok <- authorize_session(actor, session, @create_phases),
         {:ok, attrs} <- resolve_topic(session, attrs),
         :ok <- check_assignee(session.team_id, attrs["assignee_id"]) do
      case existing_by_request_id(session.team_id, attrs["client_request_id"]) do
        %ActionItem{} = item -> {:ok, preload(item)}
        nil -> insert_action(session, attrs)
      end
    end
  end

  defp insert_action(session, attrs) do
    attrs = Map.merge(attrs, %{"team_id" => session.team_id, "session_id" => session.id})

    %ActionItem{}
    |> ActionItem.create_changeset(attrs)
    |> Repo.insert()
    |> announce("action.created")
  end

  @doc """
  Changes an item: its status, its owner, its wording, when it is due
  (FR-502, FR-503).

  No phase and no session state. FR-503 is explicit that this works after the
  session closes, which is when most of it happens — a retrospective's value
  is what the team does in the fortnight afterwards.
  """
  @spec update_action(User.t() | Scope.t(), ActionItem.t(), map()) ::
          {:ok, ActionItem.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def update_action(actor, %ActionItem{} = item, attrs) do
    attrs = attrs |> stringify() |> normalise_due_date()

    with :ok <- authorize_member(actor, item.team_id),
         :ok <- check_assignee(item.team_id, attrs["assignee_id"]) do
      item
      |> ActionItem.update_changeset(attrs)
      |> Repo.update()
      |> announce("action.updated")
    end
  end

  @doc """
  Carries an item that is still open into a new session (FR-505).

  Creates a new item that links back with `carried_from`. The original is left
  as it stands — it is neither done nor dropped, it has been superseded, and
  `open_query/1` is what stops it appearing twice.
  """
  @spec carry_over(User.t() | Scope.t(), Session.t(), ActionItem.t()) ::
          {:ok, ActionItem.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def carry_over(actor, %Session{} = session, %ActionItem{} = item) do
    with :ok <- authorize_session(actor, session, @carry_phases),
         :ok <- same_team(session, item),
         :ok <- still_live(item) do
      %ActionItem{}
      |> ActionItem.create_changeset(%{
        team_id: session.team_id,
        session_id: session.id,
        assignee_id: item.assignee_id,
        carried_from_id: item.id,
        title: item.title,
        description: item.description,
        due_date: item.due_date,
        status: "open"
      })
      |> Repo.insert()
      |> announce("action.created")
    end
  end

  ## Insights input (FR-506)

  @doc """
  Completion and ageing for a team's action items (FR-506).

  Ageing is measured on the items that are still live: how long the team has
  been carrying what it has not finished. A done item's age says nothing
  useful, and averaging it in would make a team look healthier the more work
  it closed long ago.
  """
  @spec stats(Team.t(), DateTime.t()) :: map()
  def stats(%Team{} = team, now \\ DateTime.utc_now()) do
    items = Repo.all(team_query(team))
    counts = Enum.frequencies_by(items, &ActionItem.status/1)
    live = Enum.filter(items, &ActionItem.live?/1)
    ages = Enum.map(live, &age_in_days(&1, now))
    finished = Map.get(counts, :done, 0) + Map.get(counts, :dropped, 0)

    %{
      total: length(items),
      by_status: Map.new(ActionItem.statuses(), &{&1, Map.get(counts, &1, 0)}),
      completion_rate: rate(Map.get(counts, :done, 0), finished + length(live)),
      open_count: length(live),
      average_age_days: average(ages),
      oldest_open_days: Enum.max(ages, fn -> 0 end),
      overdue_count: Enum.count(live, &overdue?(&1, now))
    }
  end

  @doc """
  Whether an item's due date has passed and it is not finished (FR-506).
  """
  @spec overdue?(ActionItem.t(), DateTime.t()) :: boolean()
  def overdue?(item, now \\ DateTime.utc_now())
  def overdue?(%ActionItem{due_date: nil}, _now), do: false

  def overdue?(%ActionItem{} = item, now) do
    ActionItem.live?(item) and DateTime.compare(item.due_date, now) == :lt
  end

  @doc """
  How many days a team has been carrying an item (FR-506).
  """
  @spec age_in_days(ActionItem.t(), DateTime.t()) :: non_neg_integer()
  def age_in_days(item, now \\ DateTime.utc_now())

  def age_in_days(%ActionItem{inserted_at: inserted_at}, now) do
    div(max(DateTime.diff(now, inserted_at), 0), 86_400)
  end

  ## Internals

  defp team_query(%Team{} = team), do: from(a in ActionItem, where: a.team_id == ^team.id)

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {_key, nil}, acc -> acc
      {_key, ""}, acc -> acc
      {:status, value}, acc -> where(acc, [a], a.status == ^to_string(value))
      {:assignee_id, value}, acc -> where(acc, [a], a.assignee_id == ^value)
      {:session_id, value}, acc -> where(acc, [a], a.session_id == ^value)
      {_key, _value}, acc -> acc
    end)
  end

  defp live_status_names, do: Enum.map(ActionItem.live_statuses(), &Atom.to_string/1)

  # An action's topic is optional, and naming one that belongs to a different
  # board is not a way to link across sessions (FR-501).
  #
  # The board sends a topic key ("card:12"), because that is what the focused
  # topic is called everywhere else on that screen; the API sends the pair of
  # ids from section 6.3. Both mean the same thing.
  defp resolve_topic(session, %{"topic" => key} = attrs) when is_binary(key) and key != "" do
    case Topic.parse(key) do
      {:ok, ref} ->
        {card_id, group_id} = Topic.to_ids(ref)

        resolve_topic(
          session,
          attrs
          |> Map.drop(["topic"])
          |> Map.merge(%{"card_id" => card_id, "card_group_id" => group_id})
        )

      :error ->
        {:error, :not_found}
    end
  end

  defp resolve_topic(session, attrs) do
    case Topic.from_ids(attrs["card_id"], attrs["card_group_id"]) do
      :error ->
        if is_nil(attrs["card_id"]) and is_nil(attrs["card_group_id"]) do
          {:ok, attrs}
        else
          {:error, :not_found}
        end

      {:ok, ref} ->
        with {:ok, _confirmed} <- confirm_topic(session, ref), do: {:ok, attrs}
    end
  end

  defp confirm_topic(session, ref) do
    if ref in Enum.map(Retro.Board.topics(session, nil), &{&1.kind, &1.id}) do
      {:ok, ref}
    else
      confirm_topic_deeply(session, ref)
    end
  end

  # A card merged into a cluster is not a topic of its own, but it is still a
  # card on this board and an action may point at it.
  defp confirm_topic_deeply(session, {:card, id}) do
    if Enum.any?(Retro.Board.list_cards(session), &(&1.id == id)) do
      {:ok, {:card, id}}
    else
      {:error, :not_found}
    end
  end

  defp confirm_topic_deeply(_session, _ref), do: {:error, :not_found}

  # FR-502: "an assignee from the team". The foreign key only proves the user
  # exists; being in this team is a different question.
  #
  # A blank is the "Nobody yet" option of a select, which means no assignee
  # rather than a user whose id is the empty string.
  defp check_assignee(_team_id, value) when value in [nil, ""], do: :ok

  defp check_assignee(team_id, assignee_id) do
    if Teams.role(%User{id: assignee_id}, team_id), do: :ok, else: {:error, :not_found}
  end

  defp authorize_session(actor, %Session{} = session, phases) do
    cond do
      not Policy.see_team?(actor, Teams.role(actor, session.team_id)) -> {:error, :unauthorized}
      Session.state(session) != :active -> {:error, :session_closed}
      Session.phase(session) not in phases -> {:error, :wrong_phase}
      true -> :ok
    end
  end

  defp authorize_member(actor, team_id) do
    if Policy.see_team?(actor, Teams.role(actor, team_id)), do: :ok, else: {:error, :unauthorized}
  end

  defp same_team(session, item) do
    if session.team_id == item.team_id, do: :ok, else: {:error, :not_found}
  end

  defp still_live(item) do
    if ActionItem.live?(item), do: :ok, else: {:error, :wrong_state}
  end

  defp existing_by_request_id(_team_id, nil), do: nil

  defp existing_by_request_id(team_id, request_id) do
    Repo.get_by(ActionItem, team_id: team_id, client_request_id: request_id)
  end

  # Announced to every session the team has open, not only the one the item
  # belongs to. At check-in the item under review came from a session that has
  # already closed, while everyone watching is on the new one — broadcasting
  # to the item's own session would reach nobody (§7.3, FR-505).
  defp announce({:ok, item}, event) do
    item = preload(item)

    for session <- Retro.list_open_sessions(%Team{id: item.team_id}) do
      Events.broadcast(session.id, event, %{action_id: item.id, status: item.status})
    end

    {:ok, item}
  end

  defp announce(error, _event), do: error

  defp preload(%ActionItem{} = item), do: Repo.preload(item, @preloads, force: true)

  defp rate(_done, 0), do: 0.0
  defp rate(done, total), do: Float.round(done / total * 100, 1)

  defp average([]), do: 0.0
  defp average(values), do: Float.round(Enum.sum(values) / length(values), 1)

  # A due date is picked as a day, and stored as a timestamp (section 6.3).
  # The end of that day is what a person means by "due on the 30th" — treating
  # it as midnight would make an item overdue for the whole day it is due.
  defp normalise_due_date(%{"due_date" => date} = attrs) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} ->
        Map.put(attrs, "due_date", DateTime.new!(parsed, ~T[23:59:59], "Etc/UTC"))

      {:error, _reason} ->
        attrs
    end
  end

  defp normalise_due_date(attrs), do: attrs

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  defp user(%Scope{user: user}), do: user
  defp user(%User{} = user), do: user
  defp user(_other), do: nil
end
