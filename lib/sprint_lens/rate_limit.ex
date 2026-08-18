defmodule SprintLens.RateLimit do
  @moduledoc """
  Rate limits the API and the realtime channel, per user and per IP (NFR-202).

  Buckets are configured in `config/config.exs` as `{limit, scale_ms}`:

    * `:api` — general authenticated API and realtime intents
    * `:auth` — sign-in and password-reset attempts, which are much tighter
      because they are the ones worth brute-forcing
    * `:realtime` — board mutations arriving over the LiveView socket

  Both a per-user and a per-IP bucket are checked for every request, and the
  stricter of the two wins. A shared office NAT should not let one user exhaust
  everyone's budget, and a single user should not be able to spread an attack
  across many addresses.
  """

  use Hammer, backend: :ets

  @type bucket :: :api | :auth | :realtime
  @type result :: :ok | {:error, :rate_limited, retry_after_ms :: non_neg_integer()}

  @doc """
  Checks and increments both the user bucket and the IP bucket.

  Either identifier may be `nil` — an unauthenticated request has no user id,
  and a request from a unix socket may have no address — in which case only
  the other bucket is consulted.
  """
  @spec check(bucket(), user_id :: term() | nil, ip :: term() | nil) :: result()
  def check(bucket, user_id, ip) do
    if enabled?() do
      {limit, scale} = limits(bucket)

      [{:user, user_id}, {:ip, ip}]
      |> Enum.reject(fn {_kind, id} -> is_nil(id) end)
      |> Enum.reduce_while(:ok, fn {kind, id}, :ok ->
        case hit(key(bucket, kind, id), scale, limit) do
          {:allow, _count} -> {:cont, :ok}
          {:deny, retry_after} -> {:halt, {:error, :rate_limited, retry_after}}
        end
      end)
    else
      :ok
    end
  end

  @doc """
  The `{limit, scale_ms}` pair configured for a bucket.
  """
  @spec limits(bucket()) :: {pos_integer(), pos_integer()}
  def limits(bucket) do
    :sprint_lens
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(bucket)
  end

  @doc """
  Whether rate limiting is switched on. Tests turn it off by default so that a
  test that hammers an endpoint does not trip a limiter it is not testing.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    :sprint_lens
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.get(:enabled, true)
  end

  defp key(bucket, kind, id), do: "#{bucket}:#{kind}:#{inspect(id)}"
end
