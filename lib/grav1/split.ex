defmodule Grav1.Split do
  alias Grav1.Python

  @re_ffmpeg_frames ~r/frame= *([^ ]+?) /
  @re_ffmpeg_frames2 ~r/([0-9]+?) frames successfully decoded/
  @re_ffmpeg_keyframe ~r/n:([0-9]+)\.[0-9]+ pts:.+key:(.).+pict_type:(.)/
  @re_python_aom ~r/frame ([0-9]+)/
  @re_aom_onepass ~r/frame ([0-9]+) (0|1)/

  @ffmpeg_split_args ["-c:v", "copy"]

  @ffmpeg_split_args_reencode [
    "-c:v",
    "ffv1",
    "-g",
    "1",
    "-level",
    "3",
    "-threads",
    "16",
    "-slices",
    "30"
  ]

  @fields [
    "frame",
    "weight",
    "intra_error",
    "frame_avg_wavelet_energy",
    "coded_error",
    "sr_coded_error",
    "tr_coded_error",
    "pcnt_inter",
    "pcnt_motion",
    "pcnt_second_ref",
    "pcnt_third_ref",
    "pcnt_neutral",
    "intra_skip_pct",
    "inactive_zone_rows",
    "inactive_zone_cols",
    "MVr",
    "mvr_abs",
    "MVc",
    "mvc_abs",
    "MVrv",
    "MVcv",
    "mv_in_out_count",
    "new_mv_count",
    "duration",
    "count",
    "raw_error_stdev"
  ]

  @min_intra_level 0.25
  @boost_factor 12.5
  @intra_vs_inter_thresh 2.0
  @very_low_inter_thresh 0.05
  @kf_ii_err_threshold 2.5
  @err_change_threshold 0.4
  @ii_improvement_threshold 3.5
  @kf_ii_max 128.0

  def split(input, path_split, min_frames, max_frames, callback) do
    callback.(:log, "started split")

    callback.(:log, "getting keyframes")

    {source_keyframes, total_frames} = get_keyframes(input, callback)

    callback.(:log, "#{length(source_keyframes)} keyframes")
    callback.(:log, inspect(source_keyframes))
    callback.(:log, "getting aom keyframes")

    aom_keyframes =
      input
      |> get_aom_keyframes(total_frames, callback)
      |> kf_min_dist(min_frames, total_frames)
      |> ensure_zero()
      |> ensure_total_frames(total_frames)

    callback.(:log, inspect(aom_keyframes))

    callback.(:log, "segmenting")

    {frames, splits, segments} =
      partition_keyframes(source_keyframes, aom_keyframes, total_frames)

    {split_args, {frames, splits, segments}} =
      if length(frames) < length(aom_keyframes) / 2 do
        callback.(:log, "keyframes are unreliable, re-encoding")

        {frames, splits, segments} =
          aom_keyframes
          |> Enum.zip(tl(aom_keyframes))
          |> Enum.with_index()
          |> Enum.reduce({[], [], []}, fn {{frame, next_frame}, i}, {frames, splits, segments} ->
            length = next_frame - frame

            split_name =
              Integer.to_string(i)
              |> String.pad_leading(5, "0")

            new_split = %{file: "#{split_name}.mkv", start: frame, length: length}
            new_segment = %{file: "#{split_name}.mkv", start: 0, frames: length}

            {frames ++ [frame], splits ++ [new_split], segments ++ [new_segment]}
          end)

        {@ffmpeg_split_args_reencode, {frames, splits, segments}}
      else
        {@ffmpeg_split_args, {frames, splits, segments}}
      end

    callback.(:log, "#{length(splits)} splits, #{length(segments)} segments")

    segments = kf_max_dist(segments, max_frames)

    case split_video(input, split_args, frames, path_split, total_frames, callback) do
      ^total_frames ->
        callback.(:log, "verifying splits")

        verify_split(input, path_split, splits, callback)

        callback.(:log, "finished loading")

        {:ok, segments, total_frames}

      {:error, reason} ->
        {:error, reason}

      fr ->
        {:error, "failed to split, expected #{total_frames}, got #{to_string(fr)}"}
    end
  end

  defp split_video(input, split_args, frames, path_split, total_frames, callback) do
    args =
      [
        "-y",
        "-hide_banner",
        "-i",
        input,
        "-map",
        "0:v:0",
        "-avoid_negative_ts",
        "1",
        "-vsync",
        "0"
      ] ++
        split_args

    args =
      if length(frames) > 1 do
        args ++
          [
            "-f",
            "segment",
            "-segment_frames",
            Enum.join(tl(frames), ","),
            Path.join(path_split, "%05d.mkv")
          ]
      else
        args ++
          [
            Path.join(path_split, "00000.mkv")
          ]
      end

    callback.(:log, "splitting with ffmpeg " <> Enum.join(args, " "))

    case File.mkdir_p(path_split) do
      :ok ->
        {:ok, frames, _} =
          Port.open(
            {:spawn_executable, Grav1.get_path(:ffmpeg)},
            [:stderr_to_stdout, :exit_status, :line, args: args]
          )
          |> stream_port(0, fn line, acc ->
            case Regex.scan(@re_ffmpeg_frames, line) |> List.last() do
              [_, frame_str] ->
                {frame, _} = Integer.parse(frame_str)

                if callback != nil and acc != frame,
                  do: callback.({:progress, :splitting}, {frame, total_frames})

                frame

              _ ->
                acc
            end
          end)

        frames

      {:error, reason} ->
        {:error, "unable to create split directory. reason: #{reason}"}
    end
  end

  defp verify_split(input, path_split, splits, callback) do
    port =
      if Application.fetch_env!(:versions, :vapoursynth) != nil do
        try do
          Python.create_port()
        rescue
          _ -> nil
        end
      else
        nil
      end

    resp =
      splits
      |> Enum.with_index(1)
      |> Enum.reduce(0, fn {%{file: file, start: start, length: length} = segment, i},
                           total_frames ->
        callback.({:progress, :verify_split}, {i, length(splits)})

        path_segment = Path.join(path_split, file)

        {method, num_frames} = get_frames(path_segment, true, nil, port)

        misalignment = total_frames != start
        bad_framecount = num_frames != length

        cond do
          misalignment ->
            callback.(
              :log,
              "misalignment at #{inspect(segment)} expected: #{start}, got: #{total_frames}"
            )

          bad_framecount ->
            callback.(
              :log,
              "bad framecount #{inspect(segment)} expected: #{length}, got: #{num_frames}"
            )

          true ->
            :ok
        end

        # if not using vs
        {num_frames, bad_framecount_slow} =
          if method != :vs do
            case get_frames(path_segment, false) do
              ^num_frames ->
                {num_frames, false}

              num_frames_slow ->
                callback.(
                  :log,
                  "bad framecount #{inspect(segment)} expected: #{length}, got: #{num_frames_slow}"
                )

                {num_frames_slow, true}
            end
          else
            {num_frames, false}
          end

        if misalignment or bad_framecount or bad_framecount_slow do
          path_old = Path.join(path_split, "old")
          File.mkdir_p(path_old)
          File.rename(path_segment, Path.join(path_old, file))

          correct_split(input, path_segment, start, length, fn x ->
            callback.({:progress, :correcting}, {x, length})
          end)
        end

        callback.({:progress, :verify}, {i, length(splits)})
        total_frames + num_frames
      end)

    if port != nil do
      :python.stop(port)
    end

    resp
  end

  defp correct_split(:ffmpeg, input, output, start, length, callback) do
    args = [
      "-hide_banner",
      "-i",
      input,
      "-map",
      "0:v:0",
      "-c:v",
      "libx264",
      "-crf",
      "0",
      "-vsync",
      "0",
      "-force_key_frames",
      "expr:eq(n,#{start})",
      "-x264-params",
      "scenecut=0",
      "-vf",
      "select=gte(n\\,#{start})",
      "-frames:v",
      to_string(length),
      "-y",
      output
    ]

    Port.open(
      {:spawn_executable, Grav1.get_path(:ffmpeg)},
      [:stderr_to_stdout, :exit_status, :line, args: args]
    )
    |> stream_port(0, fn line, acc ->
      case Regex.scan(@re_ffmpeg_frames, line) |> List.last() do
        [_, frame_str] ->
          {frame, _} = Integer.parse(frame_str)
          if callback != nil and acc != frame, do: callback.(frame)
          frame

        _ ->
          acc
      end
    end)
  end

  defp correct_split(:vspipe, input, output, start, length, callback) do
    args = [
      "-u",
      "helpers/vspipe_correct_split.py",
      Grav1.get_path(:vspipe),
      Grav1.get_path(:ffmpeg),
      input,
      output,
      to_string(start),
      to_string(length)
    ]

    Port.open(
      {:spawn_executable, Grav1.get_path(:python)},
      [:exit_status, :line, :binary, args: args]
    )
    |> stream_port(0, fn line, acc ->
      case Regex.scan(@re_python_aom, line) |> List.last() do
        [_, frame_str] ->
          {frame, _} = Integer.parse(frame_str)
          if callback != nil and acc != frame, do: callback.(frame)

          frame

        _ ->
          acc
      end
    end)
    |> case do
      {:error, _} ->
        correct_split(:ffmpeg, input, output, start, length, callback)

      resp ->
        resp
    end
  end

  defp correct_split(input, output, start, length, callback) do
    if Grav1.get_path(:vspipe) != nil do
      correct_split(:vspipe, input, output, start, length, callback)
    else
      correct_split(:ffmpeg, input, output, start, length, callback)
    end
  end

  defp get_frames(:vs, input, port) do
    try do
      case port do
        nil ->
          port = Python.create_port()

          try do
            {:ok, Python.call(port, :vs_frames, :get_frames, [input])}
          rescue
            _ -> :error
          after
            :python.stop(port)
          end

        port ->
          {:ok, Python.call(port, :vs_frames, :get_frames, [input])}
      end
    rescue
      _ -> :error
    end
  end

  defp get_frames(a, b, c \\ nil, d \\ nil)

  defp get_frames(:ffmpeg, input, fast, callback) do
    fast_args = if fast, do: ["-c", "copy"], else: []
    args = ["-hide_banner", "-i", input, "-map", "0:v:0"] ++ fast_args ++ ["-f", "null", "-"]

    {:ok, frames, _} =
      Port.open(
        {:spawn_executable, Grav1.get_path(:ffmpeg)},
        [:stderr_to_stdout, :exit_status, :line, args: args]
      )
      |> stream_port(0, fn line, acc ->
        case Regex.scan(@re_ffmpeg_frames, line) |> List.last() do
          [_, frames_str] ->
            {frame, _} = Integer.parse(frames_str)
            if callback != nil and frame != acc, do: callback.(frame)
            frame

          _ ->
            acc
        end
      end)

    frames
  end

  defp get_frames(input, fast, callback, port) do
    if fast and Application.fetch_env!(:versions, :vapoursynth) != nil do
      case get_frames(:vs, input, port) do
        :error ->
          {:ffmpeg, get_frames(:ffmpeg, input, fast, callback)}

        {:ok, frames} ->
          {:vs, frames}
      end
    else
      {:ffmpeg, get_frames(:ffmpeg, input, fast, callback)}
    end
  end

  defp get_keyframes(:ebml, input, callback) do
    callback.(:log, "getting keyframes from ebml")

    try do
      port = Python.create_port()

      try do
        Python.call(port, :ebml_keyframes, :get_keyframes, [input])
      rescue
        _ -> {:undefined, :undefined}
      after
        :python.stop(port)
      end
    rescue
      _ -> {:undefined, :undefined}
    end
  end

  defp get_keyframes(:ffmpeg, input, callback) do
    callback.(:log, "getting keyframes using ffmpeg")

    args = [
      "-hide_banner",
      "-i",
      input,
      "-map",
      "0:v:0",
      "-vf",
      "select=eq(pict_type\\,PICT_TYPE_I)",
      "-f",
      "null",
      "-vsync",
      "0",
      "-loglevel",
      "debug",
      "-"
    ]

    {:ok, keyframes, lines} =
      Port.open(
        {:spawn_executable, Grav1.get_path(:ffmpeg)},
        [:stderr_to_stdout, :exit_status, :line, args: args]
      )
      |> stream_port([], fn line, acc ->
        case Regex.scan(@re_ffmpeg_keyframe, line) |> List.last() do
          [_, frame_str, key, pict_type] ->
            {frame, _} = Integer.parse(frame_str)
            callback.({:progress, :source_keyframes}, frame)

            if key == "1" and pict_type == "I" do
              acc ++ [frame]
            else
              acc
            end

          _ ->
            acc
        end
      end)

    case Regex.scan(@re_ffmpeg_frames2, Enum.join(lines)) |> List.last() do
      [_, frame_str] ->
        {frames, _} = Integer.parse(frame_str)
        {keyframes, frames}

      nil ->
        {keyframes, :undefined}
    end
  end

  defp get_keyframes(:vs, input, callback) do
    callback.(:log, "getting keyframes using vs")

    try do
      port = Python.create_port()

      try do
        Python.call(port, :vs_frames, :get_keyframes, [input])
      rescue
        _ -> get_keyframes(:ffmpeg, input, callback)
      after
        :python.stop(port)
      end
    rescue
      _ -> get_keyframes(:ffmpeg, input, callback)
    end
  end

  defp get_keyframes(input, callback) do
    case Path.extname(String.downcase(input)) do
      ".mkv" -> get_keyframes(:ebml, input, callback)
      _ -> {:undefined, :undefined}
    end
    |> case do
      {:undefined, _} ->
        if Application.fetch_env!(:versions, :vapoursynth) != nil do
          get_keyframes(:vs, input, callback)
        else
          get_keyframes(:ffmpeg, input, callback)
        end

      {frames, :undefined} ->
        callback.(:log, "getting total number of frames")
        {frames, elem(get_frames(input, true, callback), 1)}

      {frames, total_frames} ->
        {frames, total_frames}
    end
  end

  defp get_aom_keyframes(input, total_frames, callback) do
    if Grav1.get_path(:aomenc_onepass_kf) != nil do
      get_aom_keyframes_aio(input, total_frames, callback)
    else
      get_aom_keyframes_aomenc(input, total_frames, callback)
    end
  end

  defp get_aom_keyframes_aio(input, total_frames, callback) do
    callback.(:log, "getting keyframes using onepass_keyframes")

    args = [
      "-u",
      "helpers/aom_onepass.py",
      Grav1.get_path(:ffmpeg),
      Grav1.get_path(:aomenc_onepass_kf),
      input
    ]

    Port.open(
      {:spawn_executable, Grav1.get_path(:python)},
      [:exit_status, :line, args: args]
    )
    |> stream_port({[], 0}, fn line, {keyframes, frames} ->
      case Regex.scan(@re_aom_onepass, line) |> List.last() do
        [_, frame_str, is_keyframe] ->
          {frame, _} = Integer.parse(frame_str)
          callback.({:progress, :aom_keyframes}, {frame, total_frames})

          if is_keyframe == "1" or is_keyframe == 1 do
            {keyframes ++ [frame], frame}
          else
            {keyframes, frame}
          end

        _ ->
          {keyframes, frames}
      end
    end)
    |> case do
      {:ok, {keyframes, frames}, _lines} when frames + 21 >= total_frames ->
        callback.(:log, inspect(keyframes))
        keyframes

      resp ->
        callback.(:log, inspect(resp))
        get_aom_keyframes_aomenc(input, total_frames, callback)
    end
  end

  defp get_aom_keyframes_aomenc(input, total_frames, callback) do
    callback.(:log, "getting keyframes using aomenc")

    args = [
      "-u",
      "helpers/aom_firstpass.py",
      Grav1.get_path(:ffmpeg),
      Grav1.get_path(:aomenc),
      input
    ]

    Port.open(
      {:spawn_executable, Grav1.get_path(:python)},
      [:exit_status, :line, args: args]
    )
    |> stream_port(0, fn line, acc ->
      case Regex.scan(@re_python_aom, line) |> List.last() do
        [_, frame_str] ->
          {frame, _} = Integer.parse(frame_str)
          callback.({:progress, :aom_keyframes}, {frame, total_frames})
          frame

        _ ->
          acc
      end
    end)
    |> case do
      {:ok, _, _} ->
        case File.open("fpf.log", [:binary, :read]) do
          {:error, _} ->
            :error

          {:ok, file} ->
            bytes = IO.binread(file, :all)
            File.close(file)

            dict_list =
              for(<<field::little-float <- bytes>>, do: field)
              |> Enum.chunk_every(26)
              |> Enum.reduce([], fn x, acc ->
                frame_stats =
                  @fields
                  |> Enum.zip(x)
                  |> Map.new()

                acc ++ [frame_stats]
              end)

            fpf_frames = Enum.count(dict_list)

            # intentionally skipping 0th frame and last 16 frames
            kf =
              1..(fpf_frames - 16)
              |> Enum.reduce({1, [0]}, fn x, {frame_count_so_far, keyframes} ->
                if test_candidate_kf(dict_list, x, frame_count_so_far) do
                  {1, keyframes ++ [x]}
                else
                  {frame_count_so_far + 1, keyframes}
                end
              end)
              |> elem(1)

            callback.(:log, inspect(kf))
            kf
        end

      _ ->
        :error
    end
  end

  defp get_second_ref_usage_thresh(frame_count_so_far) do
    adapt_upto = 32
    min_second_ref_usage_thresh = 0.085
    second_ref_usage_thresh_max_delta = 0.035

    if frame_count_so_far >= adapt_upto do
      min_second_ref_usage_thresh + second_ref_usage_thresh_max_delta
    else
      min_second_ref_usage_thresh +
        frame_count_so_far / (adapt_upto - 1) * second_ref_usage_thresh_max_delta
    end
  end

  defp double_divide_check(x) do
    if x < 0 do
      x - 0.000001
    else
      x + 0.000001
    end
  end

  defp test_candidate_kf(dict_list, current_frame_index, frame_count_so_far) do
    previous_frame_dict = dict_list |> Enum.at(current_frame_index - 1)
    current_frame_dict = dict_list |> Enum.at(current_frame_index)
    future_frame_dict = dict_list |> Enum.at(current_frame_index + 1)

    p = previous_frame_dict
    c = current_frame_dict
    f = future_frame_dict

    qmode = true

    # todo: allow user to set whether we"re testing for constant-q mode keyframe placement or not. it"s not a big difference.

    pcnt_intra = 1.0 - c["pcnt_inter"]
    modified_pcnt_inter = c["pcnt_inter"] - c["pcnt_neutral"]

    second_ref_usage_thresh = get_second_ref_usage_thresh(frame_count_so_far)

    if not qmode or
         (frame_count_so_far > 2 and
            c["pcnt_second_ref"] < second_ref_usage_thresh and
            f["pcnt_second_ref"] < second_ref_usage_thresh and
            (c["pcnt_inter"] < @very_low_inter_thresh or
               (pcnt_intra > @min_intra_level and
                  pcnt_intra > @intra_vs_inter_thresh * modified_pcnt_inter and
                  c["intra_error"] / double_divide_check(c["coded_error"]) < @kf_ii_err_threshold and
                  (abs(p["coded_error"] - c["coded_error"]) /
                     double_divide_check(c["coded_error"]) > @err_change_threshold or
                     abs(p["intra_error"] - c["intra_error"]) /
                       double_divide_check(c["intra_error"]) > @err_change_threshold or
                     f["intra_error"] / double_divide_check(f["coded_error"]) >
                       @ii_improvement_threshold)))) do
      %{boost_score: boost_score, final_i: i} =
        Enum.reduce_while(
          0..15,
          %{boost_score: 0, old_boost_score: 0, decay_accumulator: 1, final_i: 0},
          fn i,
             %{
               boost_score: boost_score,
               old_boost_score: old_boost_score,
               decay_accumulator: decay_accumulator
             } ->
            lnf = dict_list |> Enum.at(current_frame_index + 1 + i)
            pcnt_inter = lnf["pcnt_inter"]

            next_iiratio =
              @boost_factor * lnf["intra_error"] / double_divide_check(lnf["coded_error"])

            next_iiratio = min(next_iiratio, @kf_ii_max)

            # Cumulative effect of decay in prediction quality.
            new_decay_accumulator =
              if pcnt_inter > 0.85 do
                decay_accumulator * pcnt_inter
              else
                decay_accumulator * ((0.85 + pcnt_inter) / 2.0)
              end

            # Keep a running total.
            new_boost_score = boost_score + new_decay_accumulator * next_iiratio

            # Test various breakout clauses.
            if pcnt_inter < 0.05 or
                 next_iiratio < 1.5 or
                 (pcnt_inter - lnf["pcnt_neutral"] < 0.20 and next_iiratio < 3.0) or
                 new_boost_score - old_boost_score < 3.0 or
                 lnf["intra_error"] < 200 do
              {:halt, %{boost_score: new_boost_score, final_i: i}}
            else
              {:cont,
               %{
                 boost_score: new_boost_score,
                 old_boost_score: new_boost_score,
                 decay_accumulator: new_decay_accumulator,
                 final_i: i
               }}
            end
          end
        )

      # If there is tolerable prediction for at least the next 3 frames then break out else discard this potential key frame and move on
      boost_score > 30 and i > 3
    else
      false
    end
  end

  defp kf_min_dist(aom_keyframes, min_frames, total_frames) do
    if length(aom_keyframes) > 1 and min_frames != nil and min_frames > 1 do
      aom_keyframes = aom_keyframes ++ [total_frames]

      aom_scenes =
        aom_keyframes
        |> Enum.zip(tl(aom_keyframes))

      aom_scenes
      |> Enum.zip(tl(aom_scenes) ++ [{nil, nil}])
      |> Enum.with_index()
      |> Enum.reduce({0, []}, fn x, {acc, scenes} ->
        {{{frame, next_frame}, {next_scene_frame, next_scene_next_frame}}, i} = x

        length = next_frame - frame

        scene_frame = frame - acc
        scene_length = length + acc

        cond do
          scene_length >= min_frames ->
            {0, scenes ++ [{scene_frame, scene_length}]}

          length(scenes) == 0 ->
            {scene_length, scenes}

          true ->
            {prev_frame, prev_length} = List.last(scenes)

            if i < length(aom_scenes) - 1 do
              if prev_length < min_frames do
                {acc,
                 (scenes |> Enum.reverse() |> tl() |> Enum.reverse()) ++
                   [{prev_frame, prev_length + scene_length}]}
              else
                next_scene_length = next_scene_next_frame - next_scene_frame

                if next_scene_length + scene_length < prev_length + scene_length do
                  {scene_length, scenes}
                else
                  {acc,
                   (scenes |> Enum.reverse() |> tl() |> Enum.reverse()) ++
                     [{prev_frame, prev_length + scene_length}]}
                end
              end
            else
              {acc,
               (scenes |> Enum.reverse() |> tl() |> Enum.reverse()) ++
                 [{prev_frame, prev_length + scene_length}]}
            end
        end
      end)
      |> elem(1)
      |> Enum.map(fn {frame, _} -> frame end)
    else
      aom_keyframes
    end
  end

  defp kf_max_dist(segments, max_dist) do
    if length(segments) > 1 and max_dist != nil and max_dist > 0 do
      segments
      |> Enum.reduce([], fn segment, acc ->
        if segment.frames > max_dist do
          new_segments =
            1..segment.frames
            |> Enum.reduce_while({[], segment.start, segment.frames}, fn _, acc2 ->
              {new_frames, start, frames} = acc2

              cond do
                frames < max_dist ->
                  {:halt, {new_frames ++ [{start, frames}], 0, 0}}

                frames - max_dist > max_dist ->
                  {:cont,
                   {new_frames ++ [{start, max_dist}], start + max_dist, frames - max_dist}}

                true ->
                  len = trunc(frames / 2)
                  {:cont, {new_frames ++ [{start, len}], start + len, frames - len}}
              end
            end)
            |> elem(0)
            |> Enum.map(fn {start, frames} ->
              %{file: segment.file, frames: frames, start: start}
            end)

          acc ++ new_segments
        else
          acc ++ [segment]
        end
      end)
    else
      segments
    end
    |> Enum.with_index()
    |> Enum.map(&Map.put(elem(&1, 0), :n, elem(&1, 1)))
  end

  defp ensure_zero(aom_keyframes) do
    if 0 in aom_keyframes do
      aom_keyframes
    else
      [0] ++ aom_keyframes
    end
  end

  defp ensure_total_frames(aom_keyframes, total_frames) do
    if total_frames in aom_keyframes do
      aom_keyframes
    else
      aom_keyframes ++ [total_frames]
    end
  end

  defp partition_keyframes(original_keyframes, aom_keyframes, total_frames) do
    original_keyframes = original_keyframes ++ [total_frames]

    {frames, segments, _} =
      aom_keyframes
      |> Enum.zip(tl(aom_keyframes))
      |> Enum.reduce({[], [], 0}, fn {frame, next_frame}, {frames, segments, last_end} ->
        length = next_frame - frame

        {new_frames, split_n, start} =
          if frame in original_keyframes do
            {frames ++ [frame], length(frames), 0}
          else
            largest =
              original_keyframes
              |> Enum.filter(&(&1 < frame))
              |> Enum.max()

            if largest in frames or largest < last_end do
              {frames, length(frames) - 1, frame - List.last(frames)}
            else
              {frames ++ [largest], length(frames), frame - largest}
            end
          end

        split_name =
          split_n
          |> to_string()
          |> String.pad_leading(5, "0")

        new_segment = %{file: "#{split_name}.mkv", start: start, frames: length}

        {new_frames, segments ++ [new_segment], frame + length}
      end)

    splits =
      frames
      |> Enum.zip(tl(frames) ++ [total_frames])
      |> Enum.with_index()
      |> Enum.reduce([], fn {{frame, next_frame}, i}, acc ->
        split_name =
          Integer.to_string(i)
          |> String.pad_leading(5, "0")

        acc ++ [%{file: "#{split_name}.mkv", start: frame, length: next_frame - frame}]
      end)

    {frames, splits, segments}
  end

  def stream_port_lines(port, {lines, acc}, transform) do
    receive do
      {^port, {:data, {_, data}}} ->
        new_lines = lines ++ [data]
        stream_port_lines(port, {new_lines, transform.(to_string(data), acc)}, transform)

      {^port, {:exit_status, 0}} ->
        {:ok, acc, lines}

      {^port, {:exit_status, _}} ->
        {:error, acc, lines}
    end
  end

  def stream_port(port, acc, transform) do
    stream_port_lines(port, {[], acc}, transform)
  end
end
