defmodule Grav1Web.Router do
  use Grav1Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {Grav1Web.LayoutView, :root}
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

  pipeline :admin do
    plug :ensure_admin
  end

  defp ensure_admin(conn, _) do
    if Guardian.Plug.current_resource(conn).level >= 100 do
      conn
    else
      conn
      |> put_flash(:info, "you can't do this!")
      |> redirect(to: "/")
      |> halt()
    end
  end

  scope "/", Grav1Web do
    pipe_through [:browser, :auth]

    get "/", PageController, :index
    live "/projects", ProjectsLive
    live "/projects/:id", ProjectsLive
    live "/projects/:id/:page", ProjectsLive

    live "/workers", WorkersLive
    live "/clients", ClientsLive
    live "/users", UsersLive

    scope "/" do
      pipe_through :logged_out

      live "/sign_in", SignInLive
      live "/sign_up", SignUpLive

      post "/sign_in", UserController, :sign_in
      post "/sign_up", UserController, :sign_up
    end

    scope "/" do
      pipe_through :logged_in

      scope "/user" do
        live "/", UserLive
        post "/generate_apikey", UserController, :generate_apikey
      end

      scope "/" do
        pipe_through :admin
        live "/settings", SettingsLive
      end
    end
  end

  scope "/", Grav1Web do
    pipe_through :browser

    get "/sign_out", UserController, :sign_out
  end

  scope "/api", Grav1Web do
    pipe_through :api

    post "/auth", UserController, :auth

    post "/finish_segment", ApiController, :finish_segment
    post "/add_project", ApiController, :add_project

    post "/set_workers", ApiController, :set_workers

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
