defmodule SprintLensWeb.Presence do
  @moduledoc """
  Tracks who is currently in a retrospective session and their ready state.

  Backs FR-307 (the board shows presence) and FR-213 (the facilitator sees a
  live ready count). `SprintLens.Retro.SessionServer` also watches these diffs
  to detect a facilitator disconnect (FR-207).

  Presence for a session is tracked on the topic returned by `topic/1`, keyed
  by user id. The metadata carries the display name and the ready flag for the
  phase the participant is currently in.
  """

  use Phoenix.Presence,
    otp_app: :sprint_lens,
    pubsub_server: SprintLens.PubSub

  @doc """
  The presence topic for a session.

  Distinct from the session's broadcast topic so that presence diffs do not
  interleave with board events.
  """
  @spec topic(String.t() | integer()) :: String.t()
  def topic(session_id), do: "session_presence:#{session_id}"

  @doc """
  Tracks `pid` as present in `session_id`.
  """
  @spec track_user(pid(), String.t() | integer(), integer(), map()) ::
          {:ok, binary()} | {:error, term()}
  def track_user(pid, session_id, user_id, meta \\ %{}) do
    track(pid, topic(session_id), user_id, Map.put_new(meta, :ready, false))
  end

  @doc """
  Updates the tracked metadata for `user_id`, for example to flip the ready
  flag when they mark themselves ready in the current phase (FR-213).
  """
  @spec update_user(pid(), String.t() | integer(), integer(), map()) ::
          {:ok, binary()} | {:error, term()}
  def update_user(pid, session_id, user_id, meta) do
    update(pid, topic(session_id), user_id, fn existing -> Map.merge(existing, meta) end)
  end

  @doc """
  Everyone currently in the session, as `%{user_id => meta}`.

  Only the most recent metadata entry per user is kept: one person with two
  tabs open counts once.
  """
  @spec list_users(String.t() | integer()) :: %{integer() => map()}
  def list_users(session_id) do
    session_id
    |> topic()
    |> list()
    # The tracker stringifies keys on the way out. Converting back means
    # callers compare against `user.id` without remembering to stringify.
    |> Map.new(fn {user_id, %{metas: metas}} ->
      {String.to_integer(user_id), List.last(metas)}
    end)
  end

  @doc """
  How many present participants have marked themselves ready, and how many are
  present in total (FR-213).
  """
  @spec ready_count(String.t() | integer()) :: {non_neg_integer(), non_neg_integer()}
  def ready_count(session_id) do
    users = list_users(session_id)
    ready = Enum.count(users, fn {_id, meta} -> meta[:ready] == true end)
    {ready, map_size(users)}
  end

  @doc """
  Whether `user_id` is currently connected to the session.
  """
  @spec present?(String.t() | integer(), integer()) :: boolean()
  def present?(session_id, user_id) do
    Map.has_key?(list_users(session_id), user_id)
  end
end
