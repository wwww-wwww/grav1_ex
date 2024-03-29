defmodule Grav1Web.ProjectsLive do
  use Grav1Web, :live_view

  @topic "projects_live"

  alias Grav1.{Projects, Project, RateLimit, WorkerAgent, User}
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
      |> Enum.filter(&(String.length(&1) > 0))
      |> Enum.map(&Projects.get_project(&1))
      |> Enum.filter(&(!is_nil(&1)))

    socket =
      socket
      |> assign(user: Grav1.Guardian.user(session))
      |> assign(projects: Projects.get_projects())
      |> assign(selected_projects: selected_projects)
      |> assign(project_changeset: Project.changeset(%Project{}))
      |> assign(encoder_params: Grav1.Encoder.default_params())
      |> view_project_page(page, false)

    {:ok, socket, temporary_assigns: [encoder_params: %{}]}
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
        socket.assigns.selected_projects
        |> Enum.each(&Grav1.Actions.add(&1, action, params))

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

  def handle_event("delete_project", _, socket) do
    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.selected_projects
        |> Enum.filter(&(&1.state == :ready))
        |> Projects.stop_projects()

        socket.assigns.selected_projects
        |> Enum.map(& &1.id)
        |> Projects.remove_projects()

        {:reply, %{success: true},
         socket |> assign(selected_projects: []) |> view_project_page(nil)}

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

  def handle_event(
        "set_action",
        %{
          "from_action" => from_action,
          "action" => action,
          "from_params" => from_params,
          "params" => params
        },
        socket
      ) do
    case User.has_permissions(socket) do
      :yes ->
        socket.assigns.selected_projects
        |> Enum.filter(&(&1.on_complete == from_action))
        |> Enum.filter(&(Enum.join(&1.on_complete_params, " ") == from_params))
        |> Enum.map(& &1.id)
        |> Projects.update_projects(%{on_complete: action, on_complete_params: params}, true)

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
        payload: %{projects: [project], updated_projects: [project], project_list: true}
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
          payload: %{projects: projects, updated_projects: updated_projects, project_list: true}
        },
        socket
      ) do
    handle_info(
      %{
        topic: @topic,
        event: "update_projects",
        payload: %{projects: projects, updated_projects: updated_projects}
      },
      assign(socket, projects: Projects.get_projects())
    )
  end

  # update only projects
  def handle_info(
        %{
          topic: @topic,
          event: "update_projects",
          payload: %{projects: projects, updated_projects: updated_projects}
        },
        socket
      ) do
    selected_projects =
      projects
      |> Enum.filter(&Enum.any?(socket.assigns.selected_projects, fn p -> &1.id == p.id end))

    if length(selected_projects) > 1 do
      if socket.assigns.tab == :settings do
        send_update(Grav1Web.ProjectSettingsMultiComponent,
          id: "#{Elixir.Grav1Web.ProjectSettingsMultiComponent}",
          projects: selected_projects
        )
      end
    else
      projects
      |> Enum.filter(&(&1.id in updated_projects))
      |> Enum.filter(&Enum.any?(selected_projects, fn p -> &1.id == p.id end))
      |> Enum.each(fn project ->
        if socket.assigns.tab == :settings do
          send_update(Grav1Web.ProjectSettingsComponent,
            id: "#{Elixir.Grav1Web.ProjectSettingsComponent}:#{project.id}",
            project: project
          )
        end
      end)
    end

    {:noreply, assign(socket, selected_projects: selected_projects)}
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
    if socket.assigns.tab == :logs and
         socket.assigns.selected_projects |> Enum.any?(&(&1.id == project.id)) do
      send_update(Grav1Web.ProjectLogComponent,
        id: "#{Grav1Web.ProjectLogComponent}:#{project.id}",
        log: project.log
      )
    end

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
    if socket.assigns.tab == :segments do
      send_update(Grav1Web.ProjectSegmentsComponent,
        id: "#{Grav1Web.ProjectSegmentsComponent}:#{project.id}",
        segments: segments,
        update_action: :append
      )
    end

    {:noreply, socket}
  end

  def view_project_page(socket, tab, patch \\ true) do
    if length(socket.assigns.selected_projects) > 0 do
      selected_projects =
        socket.assigns.selected_projects
        |> Enum.map(&Projects.get_project(&1.id))
        |> Enum.filter(&(!is_nil(&1)))

      if patch do
        ids = selected_projects |> Enum.map(& &1.id) |> Enum.join(",")

        socket
        |> push_patch(to: "/projects/#{ids}/#{tab}")
      else
        socket
      end
      |> assign(selected_projects: selected_projects)
      |> assign(tab: tab)
      |> assign(
        page:
          live_component(Grav1Web.ProjectPageComponent,
            id: "project_page",
            projects: selected_projects,
            page: tab,
            assigns: socket.assigns
          )
      )
    else
      assign(socket, page: nil, tab: nil)
    end
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
        project_list: true
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
  def update_projects(projects, updated_projects, project_list \\ false) do
    Endpoint.broadcast(@topic, "update_projects", %{
      projects: projects,
      updated_projects: updated_projects,
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
