defmodule SprintLensWeb.ApiErrorTest do
  use SprintLens.UnitCase, async: true

  # Asserts on English copy, so it says so rather than reading the Thai
  # translation table back to itself.
  @moduletag locale: "en"

  alias SprintLensWeb.ApiError

  describe "envelope/3" do
    @tag req: ["NFR-201"]
    test "wraps code and message in the shape section 7.1 specifies" do
      assert ApiError.envelope(:forbidden, "nope") == %{
               error: %{code: "forbidden", message: "nope"}
             }
    end

    @tag req: ["FR-401", "FR-403"]
    test "carries details a client needs to recover" do
      envelope =
        ApiError.envelope(
          :vote_budget_exceeded,
          "You have no votes left in this session.",
          %{budget: 5, used: 5}
        )

      assert envelope == %{
               error: %{
                 code: "vote_budget_exceeded",
                 message: "You have no votes left in this session.",
                 details: %{budget: 5, used: 5}
               }
             }
    end

    @tag req: ["FR-919"]
    test "omits details entirely when there are none, rather than sending null" do
      refute Map.has_key?(ApiError.envelope(:not_found, "gone").error, :details)
    end
  end

  describe "status/1" do
    @tag req: ["NFR-201"]
    test "maps authentication and authorization failures to 401 and 403" do
      assert ApiError.status(:unauthenticated) == 401
      assert ApiError.status(:invalid_credentials) == 401
      assert ApiError.status(:forbidden) == 403
    end

    @tag req: ["NFR-202"]
    test "maps rate limiting to 429" do
      assert ApiError.status(:rate_limited) == 429
    end

    @tag req: ["FR-919"]
    test "maps domain rule violations to 422 rather than 500" do
      for code <- [
            :validation_failed,
            :vote_budget_exceeded,
            :wrong_phase,
            :session_closed,
            :team_archived,
            :ai_disabled,
            :webhooks_disabled
          ] do
        assert ApiError.status(code) == 422, "expected #{code} to be a 422"
      end
    end

    @tag req: ["FR-919"]
    test "raises on an unknown code rather than inventing a status" do
      assert_raise KeyError, fn -> ApiError.status(:no_such_code) end
    end
  end

  describe "message/1" do
    @tag req: ["FR-919"]
    test "every declared code has a human-readable message" do
      for code <- ApiError.codes() do
        message = ApiError.message(code)

        assert is_binary(message) and message != "", "expected a message for #{code}"
        refute message =~ "Elixir.", "#{code} leaks a module name to the user"
      end
    end

    @tag req: ["FR-919"]
    test "reads as guidance rather than as a stack trace" do
      assert ApiError.message(:vote_budget_exceeded) == "You have no votes left in this session."
      assert ApiError.message(:internal_error) == "Something went wrong on our side."
    end
  end

  describe "codes/0" do
    @tag req: ["NFR-201"]
    test "every code has a status, so no failure mode can leak an untyped 500" do
      for code <- ApiError.codes() do
        assert is_integer(ApiError.status(code))
      end
    end
  end
end
