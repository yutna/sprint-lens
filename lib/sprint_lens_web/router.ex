defmodule SprintLensWeb.Router do
  use SprintLensWeb, :router

  import SprintLensWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SprintLensWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    # After the scope, so a signed-in user's saved language wins over the
    # browser's header (FR-907).
    plug SprintLensWeb.Plugs.Locale
    plug SprintLensWeb.Plugs.RequestContext
  end

  # Unauthenticated JSON: the health probe and the token exchange.
  pipeline :api_public do
    plug :accepts, ["json"]
    plug SprintLensWeb.Plugs.RequestContext
  end

  # Everything else under /api/v1 (section 7.1).
  pipeline :api do
    plug :accepts, ["json"]
    plug SprintLensWeb.Plugs.RequestContext
    plug SprintLensWeb.Plugs.ApiAuth
  end

  scope "/", SprintLensWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/locale/:language", LocaleController, :update
  end

  scope "/api/v1", SprintLensWeb.Api.V1 do
    pipe_through :api_public

    get "/health", HealthController, :show
    post "/tokens", TokenController, :create
  end

  scope "/api/v1", SprintLensWeb.Api.V1 do
    pipe_through :api

    get "/me", MeController, :show
    patch "/me", MeController, :update
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sprint_lens, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SprintLensWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", SprintLensWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {SprintLensWeb.UserAuth, :require_authenticated},
        SprintLensWeb.Hooks.Preferences
      ] do
      # Profile, language and theme (SCR-13). Needs only a session: sending
      # someone back to the login page to change their theme would be absurd.
      live "/users/preferences", UserLive.Preferences, :edit
    end

    # Changing an email address or a password demands a recent authentication,
    # so these live in their own live_session with the sudo-mode hook.
    live_session :require_sudo_mode,
      on_mount: [
        {SprintLensWeb.UserAuth, :require_sudo_mode},
        SprintLensWeb.Hooks.Preferences
      ] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", SprintLensWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [
        {SprintLensWeb.UserAuth, :mount_current_scope},
        SprintLensWeb.Hooks.Preferences
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
