defmodule SprintLensWeb.Router do
  use SprintLensWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SprintLensWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SprintLensWeb.Plugs.RequestContext
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug SprintLensWeb.Plugs.RequestContext
  end

  scope "/", SprintLensWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # The only endpoint that does not require authentication (§7.1).
  scope "/api/v1", SprintLensWeb.Api.V1 do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sprint_lens, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SprintLensWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
