defmodule SprintLensWeb.Api.V1.ApiTest do
  @moduledoc """
  The authenticated `/api/v1` surface: token exchange, bearer authentication
  and the current-user endpoints (section 7.1, 7.2, FR-003).
  """

  use SprintLensWeb.ConnCase

  import SprintLens.AccountsFixtures

  alias SprintLens.Accounts
  alias SprintLens.RateLimit

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  defp with_password(user \\ user_fixture()), do: set_password(user)

  defp authed(conn, user) do
    put_req_header(conn, "authorization", "Bearer " <> Accounts.create_api_token(user))
  end

  describe "POST /api/v1/tokens" do
    @tag req: ["FR-001"]
    test "exchanges an email and password for a bearer token", %{conn: conn} do
      user = with_password()

      body =
        conn
        |> post(~p"/api/v1/tokens", %{email: user.email, password: valid_user_password()})
        |> json_response(200)

      assert body["data"]["token_type"] == "bearer"
      assert Accounts.get_user_by_api_token(body["data"]["token"]).id == user.id
    end

    @tag req: ["FR-001"]
    test "accepts credentials nested under user, like the HTML form", %{conn: conn} do
      user = with_password()

      conn
      |> post(~p"/api/v1/tokens", %{
        user: %{email: user.email, password: valid_user_password()}
      })
      |> json_response(200)
    end

    @tag req: ["NFR-201"]
    test "answers identically for a wrong password and an unknown address", %{conn: conn} do
      user = with_password()

      wrong = post(conn, ~p"/api/v1/tokens", %{email: user.email, password: "nope nope nope"})
      unknown = post(conn, ~p"/api/v1/tokens", %{email: "ghost@example.com", password: "nope"})

      assert json_response(wrong, 401) == json_response(unknown, 401)
      assert json_response(wrong, 401)["error"]["code"] == "invalid_credentials"
    end

    @tag req: ["FR-005"]
    test "refuses a deactivated user even with the right password", %{conn: conn} do
      user = with_password()
      {:ok, _user} = Accounts.deactivate_user(user)

      conn
      |> post(~p"/api/v1/tokens", %{email: user.email, password: valid_user_password()})
      |> json_response(401)
    end

    @tag req: ["NFR-201"]
    test "handles a request with no credentials at all", %{conn: conn} do
      assert conn |> post(~p"/api/v1/tokens", %{}) |> json_response(401)
    end

    @tag req: ["NFR-202"]
    test "throttles repeated attempts far more tightly than the general API", %{conn: conn} do
      original = Application.fetch_env!(:sprint_lens, RateLimit)
      on_exit(fn -> Application.put_env(:sprint_lens, RateLimit, original) end)

      Application.put_env(
        :sprint_lens,
        RateLimit,
        Keyword.merge(original, enabled: true, auth: {2, 60_000})
      )

      email = "brute-#{System.unique_integer([:positive])}@example.com"
      params = %{email: email, password: "wrong"}

      post(conn, ~p"/api/v1/tokens", params)
      post(conn, ~p"/api/v1/tokens", params)
      throttled = post(conn, ~p"/api/v1/tokens", params)

      assert json_response(throttled, 429)["error"]["code"] == "rate_limited"
      assert [_retry_after] = get_resp_header(throttled, "retry-after")
    end
  end

  describe "GET /api/v1/me" do
    @tag req: ["FR-003"]
    test "returns the caller's profile", %{conn: conn} do
      user = user_fixture()

      body = conn |> authed(user) |> get(~p"/api/v1/me") |> json_response(200)

      assert body["data"]["id"] == user.id
      assert body["data"]["email"] == user.email
      assert body["data"]["display_name"] == user.display_name
      assert body["data"]["language"] == "th"
      assert body["data"]["theme"] == "system"
    end

    @tag req: ["NFR-201"]
    test "refuses a request with no token", %{conn: conn} do
      assert conn |> get(~p"/api/v1/me") |> json_response(401)
    end

    @tag req: ["NFR-201"]
    test "refuses a malformed authorization header", %{conn: conn} do
      conn
      |> put_req_header("authorization", "Token abc123")
      |> get(~p"/api/v1/me")
      |> json_response(401)
    end

    @tag req: ["NFR-201"]
    test "refuses an empty bearer token", %{conn: conn} do
      conn
      |> put_req_header("authorization", "Bearer ")
      |> get(~p"/api/v1/me")
      |> json_response(401)
    end

    @tag req: ["NFR-201"]
    test "accepts a lowercase bearer scheme", %{conn: conn} do
      user = user_fixture()
      token = Accounts.create_api_token(user)

      conn
      |> put_req_header("authorization", "bearer " <> token)
      |> get(~p"/api/v1/me")
      |> json_response(200)
    end

    @tag req: ["FR-005"]
    test "refuses a deactivated user's token", %{conn: conn} do
      user = user_fixture()
      token = Accounts.create_api_token(user)
      {:ok, _user} = Accounts.deactivate_user(user)

      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get(~p"/api/v1/me")
      |> json_response(401)
    end

    @tag req: ["NFR-202"]
    test "throttles an authenticated caller", %{conn: conn} do
      original = Application.fetch_env!(:sprint_lens, RateLimit)
      on_exit(fn -> Application.put_env(:sprint_lens, RateLimit, original) end)

      Application.put_env(
        :sprint_lens,
        RateLimit,
        Keyword.merge(original, enabled: true, api: {1, 60_000})
      )

      conn = authed(conn, user_fixture())

      get(conn, ~p"/api/v1/me")
      throttled = get(conn, ~p"/api/v1/me")

      assert json_response(throttled, 429)["error"]["code"] == "rate_limited"
    end
  end

  describe "PATCH /api/v1/me" do
    @tag req: ["FR-003"]
    test "updates the profile", %{conn: conn} do
      user = user_fixture()

      body =
        conn
        |> authed(user)
        |> patch(~p"/api/v1/me", %{display_name: "นก", language: "en", theme: "dark"})
        |> json_response(200)

      assert body["data"]["display_name"] == "นก"
      assert body["data"]["language"] == "en"
      assert body["data"]["theme"] == "dark"
    end

    @tag req: ["FR-003"]
    test "accepts fields nested under user", %{conn: conn} do
      user = user_fixture()

      body =
        conn
        |> authed(user)
        |> patch(~p"/api/v1/me", %{user: %{display_name: "Ploy"}})
        |> json_response(200)

      assert body["data"]["display_name"] == "Ploy"
    end

    @tag req: ["FR-919"]
    test "returns the section 7.1 error envelope with per-field detail", %{conn: conn} do
      {:ok, user} = Accounts.update_user_profile(user_fixture(), %{language: "en"})

      body =
        conn
        |> authed(user)
        |> patch(~p"/api/v1/me", %{language: "fr"})
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["message"] == "Some fields need attention."
      assert body["error"]["details"]["fields"]["language"] == ["is invalid"]
    end

    @tag req: ["FR-906"]
    test "answers a Thai-speaking caller in Thai", %{conn: conn} do
      body =
        conn
        |> authed(user_fixture())
        |> patch(~p"/api/v1/me", %{language: "fr"})
        |> json_response(422)

      assert body["error"]["message"] == "มีบางช่องที่ต้องแก้ไข"
      assert body["error"]["details"]["fields"]["language"] == ["ไม่ถูกต้อง"]
    end

    @tag req: ["FR-005"]
    test "cannot be used to grant yourself org-admin rights", %{conn: conn} do
      body =
        conn
        |> authed(user_fixture())
        |> patch(~p"/api/v1/me", %{is_org_admin: true})
        |> json_response(200)

      refute body["data"]["is_org_admin"]
    end
  end

  describe "unknown routes" do
    @tag req: ["FR-919"]
    test "answer with the shared error envelope, not a stack trace", %{conn: conn} do
      body = conn |> get("/api/v1/does-not-exist") |> json_response(404)

      assert body["error"]["code"] == "not_found"
      refute body["error"]["message"] =~ "Elixir."
    end
  end
end
