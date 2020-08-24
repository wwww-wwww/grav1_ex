
defmodule Grav1Web.UserSocket do
  use Phoenix.Socket

  channel("worker", Grav1Web.WorkerChannel)

  def connect(%{"token" => token}, socket, _) do
    case Guardian.Phoenix.Socket.authenticate(socket, Grav1.Guardian, token) do
      {:ok, authed_socket} ->
        {:ok,
          authed_socket
          |> assign(:socket_id, new_id())
          |> assign(:user_id, Guardian.Phoenix.Socket.current_resource(authed_socket).username)
        }
      _ -> :error
    end
  end

  def connect(_, socket, _) do
    socket_id = new_id()
    {:ok,
      socket
      |> assign(:socket_id, socket_id)
      |> assign(:user_id, "$" <> socket_id)
    }
  end

  def id(socket) do
    socket.assigns.socket_id
  end

  def new_id() do
    ret = Grav1Web.Counter.inc()
    Integer.to_string(ret)
  end
end

defmodule Grav1Web.Counter do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def inc do
    Agent.get_and_update(__MODULE__, &({&1, &1 + 1}))
  end
end
