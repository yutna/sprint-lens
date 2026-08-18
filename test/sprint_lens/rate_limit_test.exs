defmodule SprintLens.RateLimitTest do
  use SprintLens.UnitCase, async: false

  alias SprintLens.RateLimit

  # Rate limiting is off in the test environment so that tests which hammer an
  # endpoint do not trip a limiter they are not testing. These tests turn it
  # back on for themselves, and restore the setting afterwards.
  setup do
    original = Application.fetch_env!(:sprint_lens, RateLimit)
    on_exit(fn -> Application.put_env(:sprint_lens, RateLimit, original) end)

    :ok
  end

  defp configure(overrides) do
    config =
      :sprint_lens
      |> Application.fetch_env!(RateLimit)
      |> Keyword.merge(overrides)

    Application.put_env(:sprint_lens, RateLimit, config)
  end

  defp unique_id, do: System.unique_integer([:positive])

  describe "check/3" do
    @tag req: ["NFR-202"]
    test "allows requests up to the configured limit, then denies" do
      configure(enabled: true, api: {3, 60_000})
      user = unique_id()

      assert RateLimit.check(:api, user, nil) == :ok
      assert RateLimit.check(:api, user, nil) == :ok
      assert RateLimit.check(:api, user, nil) == :ok

      assert {:error, :rate_limited, retry_after} = RateLimit.check(:api, user, nil)
      assert retry_after > 0
    end

    @tag req: ["NFR-202"]
    test "limits per user, so one user cannot exhaust another's budget" do
      configure(enabled: true, api: {1, 60_000})
      noisy = unique_id()
      quiet = unique_id()

      assert RateLimit.check(:api, noisy, nil) == :ok
      assert {:error, :rate_limited, _} = RateLimit.check(:api, noisy, nil)

      assert RateLimit.check(:api, quiet, nil) == :ok
    end

    @tag req: ["NFR-202"]
    test "limits per IP, so one address cannot spread an attack across users" do
      configure(enabled: true, api: {2, 60_000})
      ip = {203, 0, 113, unique_id() |> rem(250)}

      assert RateLimit.check(:api, unique_id(), ip) == :ok
      assert RateLimit.check(:api, unique_id(), ip) == :ok

      assert {:error, :rate_limited, _} = RateLimit.check(:api, unique_id(), ip)
    end

    @tag req: ["NFR-202"]
    test "checks only the identifiers it is given" do
      configure(enabled: true, api: {1, 60_000})

      assert RateLimit.check(:api, nil, nil) == :ok
      assert RateLimit.check(:api, nil, nil) == :ok
    end

    @tag req: ["NFR-202"]
    test "keeps buckets independent, so an API burst does not lock out sign-in" do
      configure(enabled: true, api: {1, 60_000}, auth: {1, 60_000})
      user = unique_id()

      assert RateLimit.check(:api, user, nil) == :ok
      assert {:error, :rate_limited, _} = RateLimit.check(:api, user, nil)

      assert RateLimit.check(:auth, user, nil) == :ok
    end

    @tag req: ["NFR-202"]
    test "is a no-op when disabled" do
      configure(enabled: false, api: {1, 60_000})
      user = unique_id()

      for _ <- 1..10 do
        assert RateLimit.check(:api, user, nil) == :ok
      end
    end
  end

  describe "limits/1" do
    @tag req: ["NFR-202"]
    test "reads the configured limit and window for each bucket" do
      configure(enabled: true, api: {300, 60_000}, auth: {10, 60_000}, realtime: {600, 60_000})

      assert RateLimit.limits(:api) == {300, 60_000}
      assert RateLimit.limits(:auth) == {10, 60_000}
      assert RateLimit.limits(:realtime) == {600, 60_000}
    end

    @tag req: ["NFR-202"]
    test "sign-in is limited far more tightly than the general API" do
      configure(enabled: true)

      {api_limit, _} = RateLimit.limits(:api)
      {auth_limit, _} = RateLimit.limits(:auth)

      assert auth_limit < api_limit
    end
  end

  describe "enabled?/0" do
    @tag req: ["NFR-202"]
    test "reflects the configuration" do
      configure(enabled: true)
      assert RateLimit.enabled?()

      configure(enabled: false)
      refute RateLimit.enabled?()
    end
  end
end
