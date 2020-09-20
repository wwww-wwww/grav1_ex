defmodule Grav1.Concat do
  alias Grav1.{Projects, Repo}

  @re_ffmpeg_frames ~r/frame= *([^ ]+?) /
  @re_mkvmerge_frames ~r/Appending track 0 from file no. ([0-9]+)/

  def concat(project) do
    encode_path =
      Application.fetch_env!(:grav1, :path_projects)
      |> Path.join(to_string(project.id))
      |> Path.join("encode")

    segments =
      project.segments
      |> Map.values()
      |> Enum.sort_by(& &1.n)
      |> Enum.map(fn segment ->
        Path.join(encode_path, "#{segment.n}.ivf")
      end)

    output =
      Application.fetch_env!(:grav1, :path_projects)
      |> Path.join(to_string(project.id))
      |> Path.join("completed.mkv")

    Projects.update_project(project, %{state: :concatenating})

    method =
      if Application.fetch_env!(:grav1, :path_mkvmerge) != nil do
        :mkvmerge
      else
        :ffmpeg
      end

    case concat(method, project, segments, output) do
      :ok ->
        if project.on_complete != nil do
          Grav1.Actions.run_complete(project, output)
        end

        Projects.update_project(project, %{state: :completed}, true)

      {:error, reason} ->
        Projects.log(project, reason)

      message ->
        Projects.log(project, inspect(message))
    end
  end

  def concat(:ffmpeg, project, segments, output) do
    Projects.log(project, "concatenating using ffmpeg")

    case File.open("concat.txt", [:write]) do
      {:ok, file} ->
        segments
        |> Enum.each(fn segment ->
          IO.binwrite(file, "file #{segment}\n")
        end)

        :ok = File.close(file)

        args = [
          "-hide_banner",
          "-safe",
          "0",
          "-f",
          "concat",
          "-i",
          "concat.txt",
          "-c",
          "copy",
          "-y",
          output
        ]

        Projects.log(project, Enum.join(args, " "))

        port =
          Port.open(
            {:spawn_executable, Application.fetch_env!(:grav1, :path_ffmpeg)},
            [:stderr_to_stdout, :binary, :exit_status, :line, args: args]
          )

        total_frames = project.input_frames

        resp =
          Grav1.Split.stream_port(port, 0, fn line, acc ->
            case Regex.scan(@re_ffmpeg_frames, line) |> List.last() do
              [_, frame_str] ->
                {frame, _} = Integer.parse(frame_str)

                if acc != frame,
                  do:
                    Projects.update_progress(
                      project,
                      :concatenating,
                      {frame, total_frames}
                    )

                frame

              _ ->
                acc
            end
          end)

        case resp do
          {:ok, ^total_frames, _lines} ->
            :ok

          {:error, _acc, lines} ->
            {:error, Enum.join(lines, "\n")}
        end

      {:error, reason} ->
        {:error, "Error creating concat file: " <> to_string(reason)}
    end
  end

  def concat(:mkvmerge, project, segments, output) do
    Projects.log(project, "concatenating using mkvmerge")

    [first | tail] = segments

    args =
      [
        "-o",
        output,
        first
      ]
      |> Enum.concat(Enum.map(tail, &"+#{&1}"))

    Projects.log(project, Enum.join(args, " "))

    port =
      Port.open(
        {:spawn_executable, Application.fetch_env!(:grav1, :path_mkvmerge)},
        [:stderr_to_stdout, :binary, :exit_status, :line, args: args]
      )

    total_segments = length(tail)

    resp =
      Grav1.Split.stream_port(port, 0, fn line, acc ->
        case Regex.scan(@re_mkvmerge_frames, line) |> List.last() do
          [_, group] ->
            {segment, _} = Integer.parse(group)

            if acc != segment,
              do:
                Projects.update_progress(
                  project,
                  :concatenating,
                  {segment, total_segments}
                )

            segment

          _ ->
            acc
        end
      end)

    case resp do
      {:ok, ^total_segments, _lines} ->
        :ok

      {:error, _acc, lines} ->
        {:error, Enum.join(lines, "\n")}
    end
  end
end
