defmodule Grav1Web.Router do
  use Grav1Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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

    scope "/" do
      pipe_through :logged_out
      get "/sign_in", PageController, :sign_in
      post "/sign_in", UserController, :sign_in

      get "/sign_up", PageController, :sign_up
      post "/sign_up", UserController, :sign_up
    end
    
    get "/sign_out", UserController, :sign_out

    scope "/" do
      pipe_through :logged_in

      scope "/user" do
        get "/", UserController, :show_user
        post "/generate_apikey", UserController, :generate_apikey
      end
    end
  end

  scope "/api", Grav1Web do
    pipe_through :api
    post "/auth", UserController, :auth
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: Grav1Web.Telemetry
    end
  end
end
