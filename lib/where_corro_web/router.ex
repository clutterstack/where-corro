defmodule WhereCorroWeb.Router do
  use WhereCorroWeb, :router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WhereCorroWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WhereCorroWeb do
    pipe_through :browser

    live "/", PropagationLive
  end

  scope "/api", WhereCorroWeb do
    pipe_through :api

    # Keep existing
    get "/sandwich", APIController, :show
    # Add new
    post "/acknowledgment", APIController, :acknowledge
  end

  # Other scopes may use custom stacks.
  # scope "/api", WhereCorroWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:where_corro, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WhereCorroWeb.Telemetry
    end
  end
end
