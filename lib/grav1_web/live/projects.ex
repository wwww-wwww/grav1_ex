defmodule Grav1Web.ProjectsLive do
  use Grav1Web, :live_view

  @topic "projects_live"

  alias Grav1.{Projects, Project, RateLimit, Repo, WorkerAgent, User}
  alias Grav1Web.Endpoint

  def render(assigns) do
    Grav1Web.PageView.render("projects.html", assigns)
  end

  def mount(%{"id" => ids, "page" => page}, session, socket) do
    mount(%{}, session, socket, ids, String.to_atom(page))
  end

  def mount(%{"id" => ids}, session, socket) do
    mount(%{}, session, socket, ids)
  end

  def mount(_, session, socket, ids \\ "", page \\ nil) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    selected_projects =
      String.split(ids, ",")
      |> Enum.map(&Projects.get_project(&1))
      |> Enum.filter(&(!is_nil(&1)))

    socket =
      socket
      |> assign(user: Grav1.Guardian.user(session))
      |> assign(projects: Projects.get_projects())
      |> assign(selected_projects: selected_projects)
      |> assign(project_changeset: Project.changeset(%Project{}))
      |> assign(encoder_params: Grav1.Encoder.params())
      |> assign(encoder_params_json: Grav1.Encoder.params_json())
      |> view_project_page(page, false)

    {:ok, socket, temporary_assigns: [encoder_params: %{}, encoder_params_json: ""]}
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def handle_event("add_project", %{"files" => files, "params" => params}, socket) do
    case User.has_permissions(socket) do
      :yes ->
        case Projects.add_project(files, params) do
          {:error, reason} ->
            {:reply, %{success: false, reason: reason}, socket}

          _ ->
            {:reply, %{success: true}, socket}
        end

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("select_project", %{"id" => id, "multi" => multi}, socket) do
    socket =
      case Projects.get_project(id) do
        nil ->
          socket

        project ->
          if multi do
            selected_projects =
              if project.id not in Enum.map(socket.assigns.selected_projects, & &1.id) do
                socket.assigns.selected_projects ++ [project]
              else
                Enum.filter(socket.assigns.selected_projects, &(&1.id != project.id))
              end

            assign(socket, selected_projects: selected_projects)
          else
            assign(socket, selected_projects: [project])
          end
      end

    {:noreply, view_project_page(socket, socket.assigns.tab)}
  end

  def handle_event("view_project_segments", _, socket) do
    {:noreply, view_project_page(socket, :segments)}
  end

  def handle_event("view_project_log", _, socket) do
    {:noreply, view_project_page(socket, :logs)}
  end

  def handle_event("view_project_settings", _, socket) do
    {:noreply, view_project_page(socket, :settings)}
  end

  def handle_event(
        "run_complete_action",
        %{"action" => action, "params" => params},
        socket
      ) do
    case User.has_permissions(socket) do
      :yes ->
        Grav1.Actions.add(socket.assigns.page.assigns.project, action, params)
        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("start_project", _, socket) do
    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.selected_projects
        |> Enum.filter(&Grav1.Project.can_start(&1))
        |> Projects.start_projects()

        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("stop_project", _, socket) do
    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.selected_projects
        |> Enum.filter(&(&1.state == :ready))
        |> Projects.stop_projects()

        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("reset_project", %{"from" => from, "encoder_params" => params}, socket) do
    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.selected_projects
        |> Enum.filter(&(Enum.join(&1.encoder_params, " ") == from))
        |> Projects.reset_projects(params)
        |> case do
          :ok ->
            {:reply, %{success: true}, socket}

          {:error, reason} ->
            {:reply, %{success: false, reason: reason}, socket}

          err ->
            {:reply, %{success: false, reason: inspect(err)}, socket}
        end

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("set_priority", %{"from" => from, "priority" => priority}, socket) do
    {from, _} = Integer.parse(to_string(from))
    {priority, _} = Integer.parse(to_string(priority))

    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.selected_projects
        |> Enum.filter(&(&1.priority == from))
        |> Enum.map(& &1.id)
        |> Projects.update_projects(%{priority: priority}, true)

        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("set_name", %{"name" => name}, socket) do
    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.page.assigns.project
        |> Projects.update_project(%{name: name}, true)

        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event(event, payload, socket) do
    {:reply,
     %{
       success: false,
       reason: "bad event/payload</br>#{event}</br>#{inspect(payload)}"
     }, socket}
  end

  # update project and project list
  def handle_info(
        %{topic: @topic, event: "update", payload: %{project: project, project_list: true}},
        socket
      ) do
    handle_info(
      %{
        topic: @topic,
        event: "update_projects",
        payload: %{projects: [project], project_list: true}
      },
      socket
    )
  end

  # update only project list
  def handle_info(
        %{topic: @topic, event: "update_project_list", payload: %{projects: projects}},
        socket
      ) do
    {:noreply, socket |> assign(projects: projects)}
  end

  # update projects and project list
  def handle_info(
        %{
          topic: @topic,
          event: "update_projects",
          payload: %{projects: projects, project_list: true}
        },
        socket
      ) do
    handle_info(
      %{topic: @topic, event: "update_projects", payload: %{projects: projects}},
      assign(socket, projects: Projects.get_projects())
    )
  end

  # update only projects
  def handle_info(
        %{topic: @topic, event: "update_projects", payload: %{projects: projects}},
        socket
      ) do
    Enum.reduce(projects, {false, socket}, fn project, {in_selected, acc} ->
      send_update(Grav1Web.ProjectComponent,
        id: "#{Grav1Web.ProjectComponent}:#{project.id}",
        project: project
      )

      send_update(Grav1Web.ProjectSettingsComponent,
        id: "#{Grav1Web.ProjectSettingsComponent}:#{project.id}",
        project: project
      )

      if project.id in Enum.map(socket.assigns.selected_projects, & &1.id) do
        selected_projects =
          acc.assigns.selected_projects
          |> Enum.filter(&(&1.id != project.id))
          |> Enum.concat([project])

        {true, assign(acc, selected_projects: selected_projects)}
      else
        {in_selected, acc}
      end
    end)
    |> case do
      {true, socket} ->
        send_update(Grav1Web.ProjectSettingsMultiComponent,
          id: "#{Grav1Web.ProjectSettingsMultiComponent}",
          projects: socket.assigns.selected_projects
        )

        {:noreply, socket}

      {false, socket} ->
        {:noreply, socket}
    end
  end

  # update only project
  def handle_info(
        %{topic: @topic, event: "update_project", payload: %{project: project}},
        socket
      ) do
    handle_info(
      %{topic: @topic, event: "update_projects", payload: %{projects: [project]}},
      socket
    )
  end

  # update only project logs
  def handle_info(%{topic: @topic, event: "log", payload: %{project: project}}, socket) do
    send_update(Grav1Web.ProjectLogComponent,
      id: "#{Grav1Web.ProjectLogComponent}:#{project.id}",
      log: project.log
    )

    {:noreply, socket}
  end

  # update only project segments
  def handle_info(
        %{
          topic: @topic,
          event: "update_segments",
          payload: %{project: project, segments: segments}
        },
        socket
      ) do
    send_update(Grav1Web.ProjectSegmentsComponent,
      id: "#{Grav1Web.ProjectSegmentsComponent}:#{project.id}",
      segments: segments,
      update_action: :append
    )

    {:noreply, socket}
  end

  def view_project_page(socket, tab, patch \\ true) do
    socket =
      if patch do
        ids = socket.assigns.selected_projects |> Enum.map(& &1.id) |> Enum.join(",")

        socket
        |> push_patch(to: "/projects/#{ids}/#{tab}")
      else
        socket
      end
      |> assign(tab: tab)

    assign(socket,
      page:
        live_component(socket, Grav1Web.ProjectPageComponent,
          id: "project_page",
          projects: socket.assigns.selected_projects,
          page: tab,
          assigns: socket.assigns
        )
    )
  end

  def get_segments(project, workers) do
    case project.segments do
      %Ecto.Association.NotLoaded{} ->
        []

      segments ->
        workers =
          workers
          |> Enum.filter(fn worker -> worker.segment in Map.keys(segments) end)
          |> Enum.map(fn worker -> {worker.segment, {worker.progress_num, worker.pass}} end)
          |> Map.new()

        verifying =
          Grav1.VerificationExecutor.get_queue()
          |> Enum.map(fn job -> job.segment.id end)

        segments
        |> Enum.map(fn {k, segment} ->
          {progress, pass} =
            if segment.filesize == 0 do
              Map.get(workers, k, {0, 0})
            else
              {nil, nil}
            end

          %{
            id: segment.id,
            n: segment.n,
            pass: pass,
            progress: progress,
            frames: segment.frames,
            filesize: segment.filesize,
            verifying: segment.id in verifying
          }
        end)
        |> Enum.sort_by(& &1.n)
    end
  end

  def map_changed_segments(segments) do
    verifying =
      Grav1.VerificationExecutor.get_queue()
      |> Enum.map(fn job -> job.segment.id end)

    segments
    |> Enum.map(fn {segment, workers} ->
      {progress, pass} =
        if length(workers) > 0 and segment.filesize == 0 do
          workers
          |> Enum.map(&{&1.progress_num, &1.pass})
          |> Enum.at(0)
        else
          {nil, nil}
        end

      %{
        id: segment.id,
        n: segment.n,
        pass: pass,
        progress: progress,
        frames: segment.frames,
        filesize: segment.filesize,
        verifying: segment.id in verifying
      }
    end)
  end

  def get_segments(project) do
    get_segments(project, WorkerAgent.get_workers())
  end

  # update project list and project
  def update(project, ratelimit \\ false) do
    if not ratelimit or RateLimit.can_execute?("projects", 1 / 10) do
      Endpoint.broadcast(@topic, "update", %{
        project: project,
        projects: true
      })
    end
  end

  # update only project
  def update_project(project, ratelimit \\ false) do
    if not ratelimit or RateLimit.can_execute?("project:#{project.id}", 1 / 10) do
      Endpoint.broadcast(@topic, "update_project", %{project: project})
    end
  end

  # update projects
  def update_projects(projects, project_list \\ false) do
    Endpoint.broadcast(@topic, "update_projects", %{
      projects: projects,
      project_list: project_list
    })

    projects
  end

  # update only log of project
  def update_log(project) do
    Endpoint.broadcast(@topic, "log", %{
      project: project
    })
  end

  # update only segments of project
  def update_segments(project, changed_segments) do
    Grav1Web.Endpoint.broadcast(@topic, "update_segments", %{
      project: project,
      segments: map_changed_segments(changed_segments)
    })
  end

  # update only project list
  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "update_project_list", %{
      projects: Projects.get_projects()
    })
  end
end
