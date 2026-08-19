defmodule SprintLens.AI do
  @moduledoc """
  Asking a model for a suggestion, and what a human does with it (AI-001 to
  AI-018).

  ## Nothing here writes to the board

  AI-002 says "a human MUST review and accept, edit, or reject it; nothing is
  applied automatically". That is enforced architecturally rather than by a
  review step: accepting a clustering suggestion calls
  `SprintLens.Retro.Board.create_group/4`, accepting an action draft fills in
  the form that calls `SprintLens.Actions.create_action/3`, and this module
  has no `Repo.insert` for a card, a group or an action anywhere in it. The
  only row it writes is the suggestion itself.

  ## Three gates, checked three times

  AI-003 needs the team to have opted in (FR-105) *and* the global switch to
  be off (FR-806). `available?/1` answers both, and it is consulted when a
  suggestion is requested, when the controls are rendered, and again inside
  the worker — because a switch flipped while a job sat in the queue has to
  stop that job too, exactly as it does for webhooks.

  ## What gets logged

  AI-017: type, timing, size and outcome. Never the prompt and never the
  answer. The suggestion row keeps the output because a human has to read it;
  the log keeps only what an operator needs at three in the morning.
  """

  import Ecto.Query, warn: false

  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Admin
  alias SprintLens.AI.Scope, as: InputScope
  alias SprintLens.AI.Suggestion
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLens.Teams.Team
  alias SprintLens.Workers.AiSuggestion, as: Worker

  ## Events (AI-005)

  @doc """
  The topic a team's AI activity is announced on.

  Deliberately not one of section 7.3's session events: that list is the
  realtime contract for a live board and this is not part of it. AI-005 says
  "the UI polls or receives an event when a suggestion is ready" — this is
  the event, on a topic of its own, so §7.3 stays exactly as written.
  """
  @spec topic(term()) :: String.t()
  def topic(team_id), do: "ai:team:#{team_id}"

  @doc """
  Subscribes the calling process to a team's AI activity (AI-005).
  """
  @spec subscribe(term()) :: :ok | {:error, term()}
  def subscribe(team_id), do: Phoenix.PubSub.subscribe(SprintLens.PubSub, topic(team_id))

  ## Availability (AI-001, AI-003)

  @doc """
  Whether this team may use AI at all (AI-003).

  Both halves: the organisation's kill switch (FR-806) and the team's own
  opt-in (FR-105). Either one being off is enough.
  """
  @spec available?(Team.t() | nil) :: boolean()
  def available?(nil), do: false
  def available?(%Team{ai_opt_in: false}), do: false
  def available?(%Team{}), do: Admin.ai_enabled?()

  @doc """
  Whether `actor` may ask this team for a suggestion.

  Any member: AI-011 has "a participant" drafting an action, and AI-009 has
  the facilitator reviewing a summary — the reviewing is where the roles
  differ, not the asking.
  """
  @spec can_request?(User.t() | Scope.t() | nil, Team.t()) :: boolean()
  def can_request?(actor, %Team{} = team) do
    available?(team) and Policy.see_team?(actor, Teams.role(actor, team))
  end

  ## Reading

  @doc """
  A team's suggestions, newest first.
  """
  @spec list_suggestions(Team.t(), keyword()) :: [Suggestion.t()]
  def list_suggestions(%Team{} = team, filters \\ []) do
    team
    |> team_query()
    |> apply_filters(filters)
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> Repo.all()
  end

  @doc """
  The suggestions attached to one session.
  """
  @spec list_session_suggestions(Session.t(), Suggestion.type() | nil) :: [Suggestion.t()]
  def list_session_suggestions(%Session{} = session, type \\ nil) do
    query = from s in Suggestion, where: s.session_id == ^session.id

    query
    |> then(fn q -> if type, do: where(q, [s], s.type == ^Atom.to_string(type)), else: q end)
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> Repo.all()
  end

  @doc """
  One suggestion the caller's membership lets them see.
  """
  @spec fetch_suggestion(User.t() | Scope.t() | nil, term()) ::
          {:ok, Suggestion.t()} | {:error, :not_found}
  def fetch_suggestion(actor, id) do
    with %Suggestion{} = suggestion <- Repo.fetch(Suggestion, id),
         true <- Policy.see_team?(actor, Teams.role(actor, suggestion.team_id)) do
      {:ok, suggestion}
    else
      _no_access -> {:error, :not_found}
    end
  end

  ## Requesting (AI-005)

  @doc """
  Asks for a suggestion, and queues the job that will produce it (AI-005).

  Returns immediately with a `queued` row: AI work is asynchronous by
  requirement, and the screen that asked for it shows a slot rather than
  waiting.
  """
  @spec request(User.t() | Scope.t(), Team.t(), Suggestion.type(), map()) ::
          {:ok, Suggestion.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def request(actor, %Team{} = team, type, context \\ %{}) do
    with :ok <- authorize(actor, team),
         {:ok, type} <- parse_type(type),
         {:ok, input, scope} <- InputScope.build(type, Map.put(context, :team, team)) do
      %Suggestion{}
      |> Suggestion.request_changeset(%{
        team_id: team.id,
        session_id: context[:session] && context[:session].id,
        requested_by_id: user_id(actor),
        type: Atom.to_string(type),
        input_scope: Enum.join(scope, ","),
        input_bytes: InputScope.size(input)
      })
      |> Repo.insert()
      |> enqueue(context)
    end
  end

  @doc """
  Asks again for one that failed (AI-006).

  A fresh row rather than a reset one: the failure is part of the record, and
  an operator asking "how often does this provider time out?" needs the
  attempts to still be countable.
  """
  @spec retry(User.t() | Scope.t(), Suggestion.t(), map()) ::
          {:ok, Suggestion.t()} | {:error, atom()}
  def retry(actor, %Suggestion{} = suggestion, context \\ %{}) do
    with {:ok, team} <- fetch_team(suggestion.team_id),
         {:ok, type} <- parse_type(Suggestion.type(suggestion)) do
      context =
        case suggestion.session_id do
          nil -> context
          id -> Map.put_new_lazy(context, :session, fn -> load_session(id) end)
        end

      request(actor, team, type, context)
    end
  end

  ## The job's own updates (AI-005, AI-006)

  @doc """
  Marks a suggestion as running, so a screen can say so.
  """
  @spec mark_running(Suggestion.t()) :: {:ok, Suggestion.t()} | {:error, Ecto.Changeset.t()}
  def mark_running(%Suggestion{} = suggestion) do
    suggestion |> Suggestion.result_changeset(%{status: "running"}) |> Repo.update()
  end

  @doc """
  Stores what the model said (AI-005).
  """
  @spec store_result(Suggestion.t(), map(), non_neg_integer()) ::
          {:ok, Suggestion.t()} | {:error, Ecto.Changeset.t()}
  def store_result(%Suggestion{} = suggestion, %{content: content}, duration_ms) do
    suggestion
    |> Suggestion.result_changeset(%{
      status: "ready",
      output: content,
      duration_ms: duration_ms
    })
    |> Repo.update()
    |> announce()
  end

  @doc """
  Records that the job did not work, so the slot can offer a retry (AI-006).
  """
  @spec store_failure(Suggestion.t(), term(), non_neg_integer()) ::
          {:ok, Suggestion.t()} | {:error, Ecto.Changeset.t()}
  def store_failure(%Suggestion{} = suggestion, reason, duration_ms) do
    suggestion
    |> Suggestion.result_changeset(%{
      status: "failed",
      error: inspect(reason),
      duration_ms: duration_ms
    })
    |> Repo.update()
    |> announce()
  end

  ## Decisions (AI-002)

  @doc """
  Accepts a suggestion, optionally with the human's edits (AI-002).

  What acceptance *does* depends on the feature, and in every case it is an
  existing function elsewhere: a summary attaches to the recap here, a
  cluster goes through `Board.create_group/4`, an action draft fills in the
  form. This module never writes to the board.
  """
  @spec accept(User.t() | Scope.t(), Suggestion.t(), String.t() | nil) ::
          {:ok, Suggestion.t()} | {:error, atom()}
  def accept(actor, %Suggestion{} = suggestion, edited \\ nil) do
    with :ok <- authorize_decision(actor, suggestion),
         :ok <- require_ready(suggestion) do
      content = edited || suggestion.output

      Repo.transact(fn ->
        with {:ok, accepted} <- decide(suggestion, :accepted, content) do
          apply_acceptance(accepted, content)
        end
      end)
    end
  end

  @doc """
  Rejects a suggestion (AI-002).
  """
  @spec reject(User.t() | Scope.t(), Suggestion.t()) :: {:ok, Suggestion.t()} | {:error, atom()}
  def reject(actor, %Suggestion{} = suggestion) do
    with :ok <- authorize_decision(actor, suggestion),
         :ok <- require_ready(suggestion) do
      decide(suggestion, :rejected, nil)
    end
  end

  ## Internals

  defp apply_acceptance(%Suggestion{type: "session_summary"} = suggestion, content) do
    # The accepted text is copied onto the session rather than read back
    # through the suggestion, so purging the suggestions cannot empty a
    # recap somebody signed off (AI-009, AI-018).
    {:ok, _updated} =
      suggestion.session_id
      |> load_session()
      |> Session.summary_changeset(content)
      |> Repo.update()

    {:ok, suggestion}
  end

  defp apply_acceptance(suggestion, _content), do: {:ok, suggestion}

  defp decide(suggestion, status, content) do
    suggestion
    |> Suggestion.decision_changeset(status, content)
    |> Repo.update()
    |> announce()
  end

  # Matched on success alone: the changeset was validated above and every
  # reference in it was just fetched, so a failure here means an invariant
  # broke rather than something a caller can fix.
  defp enqueue({:ok, suggestion}, context) do
    %{"suggestion_id" => suggestion.id, "context" => job_context(context)}
    |> Worker.new()
    |> Oban.insert()

    {:ok, suggestion}
  end

  # Only the small extras a feature needs; the content itself is rebuilt from
  # the database when the job runs, so nothing sensitive sits in a job row.
  defp job_context(context) do
    context
    |> Map.take([:topic, :note, :text, :language])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp announce({:ok, %Suggestion{} = suggestion}) do
    Phoenix.PubSub.broadcast(SprintLens.PubSub, topic(suggestion.team_id), {
      :ai_suggestion,
      %{
        suggestion_id: suggestion.id,
        type: suggestion.type,
        status: suggestion.status,
        session_id: suggestion.session_id
      }
    })

    {:ok, suggestion}
  end

  defp authorize(actor, %Team{} = team) do
    cond do
      not Policy.see_team?(actor, Teams.role(actor, team)) -> {:error, :unauthorized}
      not available?(team) -> {:error, :ai_disabled}
      true -> :ok
    end
  end

  defp authorize_decision(actor, %Suggestion{} = suggestion) do
    with {:ok, team} <- fetch_team(suggestion.team_id), do: authorize(actor, team)
  end

  defp require_ready(%Suggestion{} = suggestion) do
    if Suggestion.status(suggestion) == :ready, do: :ok, else: {:error, :wrong_state}
  end

  defp parse_type(type) do
    case Suggestion.parse_type(type) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, :not_found}
    end
  end

  # `get!` rather than a nil branch: a suggestion's team cannot be missing,
  # because deleting a team deletes its suggestions (AI-018).
  defp fetch_team(team_id), do: {:ok, Repo.get!(Team, team_id)}

  # Same reasoning: a summary suggestion always has a session — `Scope.build`
  # refuses to make one without — and deleting a session deletes it.
  defp load_session(id), do: Session |> Repo.get!(id) |> Retro.preload()

  defp team_query(%Team{} = team), do: from(s in Suggestion, where: s.team_id == ^team.id)

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:type, value}, acc -> where(acc, [s], s.type == ^to_string(value))
      {:status, value}, acc -> where(acc, [s], s.status == ^to_string(value))
      {_key, _value}, acc -> acc
    end)
  end

  defp user_id(%Scope{user: user}), do: user_id(user)
  defp user_id(%User{id: id}), do: id
end
