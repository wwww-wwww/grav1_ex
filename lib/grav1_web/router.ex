defmodule Grav1Web.Router do
  use Grav1Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_root_layout, {Grav1Web.LayoutView, :app}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug Grav1.Pipeline
  end

  pipeline :logged_in do
    plug Guardian.Plug.EnsureAuthenticated
  end

  pipeline :logged_out do
    plug Guardian.Plug.EnsureNotAuthenticated
  end

  scope "/", Grav1Web do
    pipe_through [:browser, :auth]

    get "/", PageController, :index
    live "/projects", ProjectsLive
    live "/projects/:id", ProjectsLive

    live "/workers", WorkersLive

    scope "/" do
      pipe_through :logged_out

      live "/sign_in", SignInLive
      live "/sign_up", SignUpLive

      post "/sign_in", UserController, :sign_in
      post "/sign_up", UserController, :sign_up
    end

    get "/sign_out", UserController, :sign_out

    scope "/" do
      pipe_through :logged_in

      scope "/user" do
        live "/", UserLive
        post "/generate_apikey", UserController, :generate_apikey
      end
    end
  end

  scope "/api", Grav1Web do
    pipe_through :api

    post "/auth", UserController, :auth
    
    post "/finish_segment", ApiController, :finish_segment
    post "/add_project", ApiController, :add_project

    get "/segment/:id", ApiController, :get_segment
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: Grav1Web.Telemetry
    end
  end
end
