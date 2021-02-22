defmodule Grav1.Concat do
  alias Grav1.Projects

  @re_ffmpeg_frames ~r/frame= *([^ ]+?) /
  @re_mkvmerge_frames ~r/Appending track 0 from file no. ([0-9]+)/
  @re_mkvmerge_track_v ~r/Track ID ([0-9]+?): video/

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

    case concat(project, segments, output) do
      :ok ->
        if project.on_complete != nil do
          Grav1.Actions.add(project, project.on_complete, project.on_complete_params)
        end

        Projects.update_project(project, %{state: :completed}, true)

      {:error, reason} ->
        Projects.log(project, reason)

      message ->
        Projects.log(project, inspect(message))
    end
  end

  def concat(project, segments, output) do
    Grav1.get_path(:mkvmerge)
    |> case do
      nil -> :ffmpeg
      _ -> :mkvmerge
    end
    |> concat(project, segments, "#{output}.tmp.mkv")
    |> case do
      {:ok, tmp} ->
        if project.copy_timestamps and Grav1.get_path(:mkvextract) do
          copy_timestamps(project, tmp, output)
        else
          File.rename(tmp, output)
          :ok
        end

      message ->
        message
    end
  end

  def get_trackid(file) do
    case System.cmd(Grav1.get_path(:mkvmerge), ["--identify", file], stderr_to_stdout: true) do
      {out, 0} ->
        case Regex.run(@re_mkvmerge_track_v, out) do
          [_, trackid] -> trackid
          nil -> 0
        end

      {resp, 1} ->
        {:error, resp}
    end
  end

  def copy_timestamps(project, from, to) do
    timestamps_file =
      Application.fetch_env!(:grav1, :path_projects)
      |> Path.join(to_string(project.id))
      |> Path.join("timestamps.txt")

    Projects.log(project, "Getting track id")

    trackid = get_trackid(project.input)

    Projects.log(project, "Extracting timestamps for track #{trackid}")

    extract = [project.input, "timestamps_v2", "#{trackid}:#{timestamps_file}"]

    case System.cmd(Grav1.get_path(:mkvextract), extract, stderr_to_stdout: true) do
      {_, 0} ->
        Projects.log(project, "Extracted timestamps")
        merge = ["--timestamps", "0:#{timestamps_file}", from, "-o", to]

        case System.cmd(Grav1.get_path(:mkvmerge), merge, stderr_to_stdout: true) do
          {_, 0} ->
            Projects.log(project, "Merged timestamps")
            File.rm(from)

          {resp, 1} ->
            {:error, resp}
        end

      {resp, 1} ->
        {:error, resp}
    end
  end

  def concat(:ffmpeg, project, segments, output) do
    Projects.log(project, "Concatenating using ffmpeg")

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

        total_frames = project.input_frames

        Port.open(
          {:spawn_executable, Grav1.get_path(:ffmpeg)},
          [:stderr_to_stdout, :binary, :exit_status, :line, args: args]
        )
        |> Grav1.Split.stream_port(0, fn line, acc ->
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
        |> case do
          {:ok, ^total_frames, _lines} ->
            {:ok, output}

          {:error, _acc, lines} ->
            {:error, Enum.join(lines, "\n")}
        end

      {:error, reason} ->
        {:error, "Error creating concat file: " <> to_string(reason)}
    end
  end

  def concat(:mkvmerge, project, segments, output, flip \\ 0) do
    Projects.log(project, "Concatenating using mkvmerge")

    path_mkvmerge = Grav1.get_path(:mkvmerge)

    [first | tail] = segments

    args = [
      "-o",
      "#{output}.#{flip}.mkv",
      first
    ]

    cmd_size = String.length(Enum.join([path_mkvmerge] ++ args, " "))

    {args, remaining, _} =
      tail
      |> Enum.reduce({args, [], cmd_size}, fn segment, acc ->
        {args, remaining, size} = acc

        if size > 32767 do
          {args, remaining ++ [segment], size}
        else
          new_size = size + String.length(segment) + 2

          if new_size > 32767 do
            {args, remaining ++ [segment], new_size}
          else
            {args ++ ["+#{segment}"], remaining, new_size}
          end
        end
      end)

    Projects.log(project, Enum.join(args, " "))

    total_segments = length(args) - 3

    Port.open(
      {:spawn_executable, path_mkvmerge},
      [:stderr_to_stdout, :binary, :exit_status, :line, args: args]
    )
    |> Grav1.Split.stream_port(0, fn line, acc ->
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
    |> case do
      {:ok, ^total_segments, _lines} ->
        if length(remaining) > 0 do
          new_flip = if flip == 0, do: 1, else: 0
          concat(:mkvmerge, project, ["#{output}.#{flip}.mkv"] ++ remaining, output, new_flip)
        else
          {:ok, "#{output}.#{flip}.mkv"}
        end

      {:error, _acc, lines} ->
        {:error, Enum.join(lines, "\n")}
    end
  end
end
