defmodule Grav1.Split do

  @re_ffmpeg_frames ~r/frame= *([^ ]+?) /
  @re_ffmpeg_frames2 ~r/([0-9]+?) frames successfully decoded/
  @re_ffmpeg_keyframe ~r/n:([0-9]+)\.[0-9]+ pts:.+key:(.).+pict_type:(.)/
  @re_python_aom ~r/frame *([^ ]+)/

  @fields [
    "frame", "weight", "intra_error", "frame_avg_wavelet_energy",
    "coded_error", "sr_coded_error", "tr_coded_error", "pcnt_inter",
    "pcnt_motion", "pcnt_second_ref", "pcnt_third_ref", "pcnt_neutral",
    "intra_skip_pct", "inactive_zone_rows", "inactive_zone_cols", "MVr",
    "mvr_abs", "MVc", "mvc_abs", "MVrv", "MVcv", "mv_in_out_count",
    "new_mv_count", "duration", "count", "raw_error_stdev"
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
    IO.inspect("started split")
    {source_keyframes, total_frames} = get_keyframes(input, fn x -> callback.(:source_keyframes, x) end)

    aom_keyframes = get_aom_keyframes(input, fn x -> callback.(:aom_keyframes, x, total_frames) end)
    |> kf_min_dist(min_frames, total_frames)
    |> ensure_total_frames(total_frames)
    |> kf_max_dist(min_frames, max_frames, source_keyframes)

    {frames, splits, segments} = partition_keyframes(source_keyframes, aom_keyframes, total_frames)

    # 

    {source_keyframes, aom_keyframes}
  end

  def verify_split(input, path_split, segments, callback) do
    segments
    |> Enum.with_index(1)
    |> Enum.reduce(0, fn {segment, i}, total_frames ->
      %{file: file, n: n, start: start, length: length} = segment

      path_segment = Path.join(path_split, file)

      num_frames = get_frames(path_segment)

      misalignment = total_frames != start
      if misalignment, do: callback.(:log, "misalignment at #{segment} expected: #{start}, got: #{total_frames}")

      bad_framecount = num_frames != length
      if bad_framecount, do: callback.(:log, "bad framecount #{segment} expected: #{length}, got: #{num_frames}")

      bad_framecount_slow = true and case get_frames(path_segment, false) do # if not using vs_ffms2
        ^num_frames -> false
        num_frames_slow ->
          callback.(:log, "bad framecount #{segment} expected: #{num_frames}, got: #{num_frames_slow}")
          true
      end

      if misalignment or bad_framecount or bad_framecount_slow do
        path_old = Path.join(path_split, "old")
        File.mkdir_p(path_old)
        File.rename(path_segment, Path.join(path_old, file))
        correct_split(input, path_segment, start, length, fn x -> callback.(:correct, x) end)
      end

      if callback != nil, do: callback.(:verify, i)
      total_frames + num_frames
    end) 
  end

  def correct_split(input, output, start, length, callback) do
    port = Port.open(
      {:spawn_executable, Application.fetch_env!(:grav1, :path_python)},
      [
        :binary,
        :exit_status,
        args: [
          "-u",
          "vspipe_correct_split.py",
          Application.fetch_env!(:grav1, :path_vspipe),
          Application.fetch_env!(:grav1, :path_ffmpeg),
          input,
          output,
          start,
          length
        ]
      ]
    )
    
    stream_port(port, 0, fn line, acc ->
      case Regex.run(@re_python_aom, line) do
        nil -> acc
        [_, frame_str] ->
          case Integer.parse(frame_str) do
            :error -> acc
            {new_frame, _} ->
              if callback != nil and acc != new_frame, do: callback.(new_frame)

              new_frame
          end
      end
    end)
  end

  defp stream_port(port, acc, transform, line \\ "") do
    receive do
      {^port, {:data, data}} ->
        new_line = line <> data
        case :binary.match(new_line, "\n") do
          :nomatch -> stream_port(port, acc, transform, new_line)
          _ ->
            {new_acc, remaining} = Regex.split(~r/(?<=\n)/, new_line)
            |> Enum.reduce({acc, ""}, fn x, {inner_acc, inner_line} ->
              if String.ends_with?(x, "\n") do
                {transform.(x, inner_acc), ""}
              else
                {inner_acc, x}
              end
            end)
            stream_port(port, new_acc, transform, remaining)
        end
      {^port, {:exit_status, 0}} ->
        if String.length(line) > 0 do
          transform.(line, acc)
        else
          acc
        end
      {^port, {:exit_status, status}} ->
        {:error, status, acc}
    end
  end

  def get_frames(input, fast \\ true, callback \\ nil) do
    if fast and false do # vapoursynth
    else
      fast_args = if fast, do: ["-c", "copy"], else: []
      args = ["-i", input] ++ fast_args ++ ["-f", "null", "-"]

      port = Port.open(
        {:spawn_executable, Application.fetch_env!(:grav1, :path_ffmpeg)},
        [:stderr_to_stdout, :binary, :exit_status, args: args]
      )
      
      stream_port(port, 0, fn line, acc ->
        case Regex.run(@re_ffmpeg_frames, line) do
          nil -> acc
          [_, frames_str] ->
            case Integer.parse(frames_str) do
              :error -> acc
              {new_frames, _} ->
                if callback != nil and new_frames != acc, do: callback.(new_frames)

                new_frames
            end
        end
      end)
    end
  end

  defp get_keyframes(input, callback \\ nil) do
    {frames, total_frames} = case Path.extname(String.downcase(input)) do
      ".mkv" -> {:nothing, :nothing}#get_keyframes_ebml(input)
      _ -> {:nothing, :nothing}
    end

    case {frames, total_frames} do
      {:nothing, _} ->
        if false do # if vapoursynth supported
          get_keyframes_vs_ffms2(input)
        else
          get_keyframes_ffmpeg(input, callback)
        end
      {frames, :nothing} ->
        {frames, get_frames(input, true, callback)}
    end
  end

  defp get_keyframes_ebml(input) do
    
  end

  defp get_keyframes_vs_ffms2(input) do
    
  end

  def get_keyframes_ffmpeg(input, callback \\ nil) do
    args = [
      "-hide_banner",
      "-i", input,
      "-map", "0:v:0",
      "-vf", "select=eq(pict_type\\,PICT_TYPE_I)",
      "-f", "null",
      "-vsync", "0",
      "-loglevel", "debug", "-"
    ]
  
    port = Port.open(
      {:spawn_executable, Application.fetch_env!(:grav1, :path_ffmpeg)},
      [:stderr_to_stdout, :binary, :exit_status, args: args]
    )
    
    stream_port(port, {[], 0}, fn line, acc ->
      {keyframes, frames} = acc

      case Regex.run(@re_ffmpeg_keyframe, line) do
        nil ->
          case Regex.run(@re_ffmpeg_frames2, line) do
            nil -> acc
            [_, frame_str] ->
              case Integer.parse(frame_str) do
                :error -> acc
                {new_frame, _} ->
                  if callback != nil and frames != new_frame, do: callback.(new_frame)

                  {keyframes, new_frame}
              end
          end
        [_, frame_str, key, pict_type] ->
          case Integer.parse(frame_str) do
            :error -> acc
            {new_frame, _} ->
              if callback != nil and frames != new_frame, do: callback.(new_frame)

              if key == "1" and pict_type == "I", do: {keyframes ++ [new_frame], frames}, else: acc
          end
      end

    end)
  end

  defp pipe(port1, port2) do
    receive do
      {^port1, {:exit_status, status}} ->
        IO.inspect("port1 exited, status #{status}")
      {^port2, {:exit_status, status}} ->
        IO.inspect("port2 exited, status #{status}")
      {^port2, {:data, data}} ->
        IO.inspect(data)
        pipe(port1, port2)
      {^port1, {:data, data}} ->
        Port.command(port2, data)
        pipe(port1, port2)
      b ->
        IO.inspect(b)
    end
  end

  def get_aom_keyframes(input, callback \\ nil) do
    _ = """
    ffmpeg_args = ["-i", input, "-pix_fmt", "yuv420p", "-map", "0:v:0", "-vsync", "0", "-strict", "-1", "-f", "yuv4mpegpipe", "-"]

    null = case :os.type do
      {:win32, _} -> "NUL"
      _ -> "/dev/null"
    end

    aomenc_args = ["-", "-o", null, "--ivf", "--passes=2", "--fpf=fpf.log", "--pass=1", "--auto-alt-ref=1", "-w", "1280", "-h", "720"]

    port_ffmpeg = Port.open(
      {:spawn_executable, Application.fetch_env!(:grav1, :path_ffmpeg)},
      [:binary, :exit_status, args: ffmpeg_args]
    )

    port_aomenc = Port.open(
      {:spawn_executable, Application.fetch_env!(:grav1, :path_aomenc)},
      [:stderr_to_stdout, :binary, :exit_status, args: aomenc_args]
    )

    pipe(port_ffmpeg, port_aomenc)
    """
    # until i can get piping to work
    port = Port.open(
      {:spawn_executable, Application.fetch_env!(:grav1, :path_python)},
      [:binary, :exit_status, args: ["-u", "aom_firstpass.py", input]]
    )
    
    result = stream_port(port, 0, fn line, acc ->
      case Regex.run(@re_python_aom, line) do
        nil -> acc
        [_, frame_str] ->
          case Integer.parse(frame_str) do
            :error -> acc
            {new_frame, _} ->
              if callback != nil and acc != new_frame, do: callback.(new_frame)

              new_frame
          end
      end
    end)

    case result do
      {:error, _} -> :error
      _ ->
        filename = "fpf.log"

        case File.open(filename, [:binary, :read]) do
          {:error, _} -> :error
          {:ok, file} ->
            bytes = IO.binread(file, :all)
            File.close(file)

            dict_list = (for <<field::little-float <- bytes>>, do: field)
            |> Enum.chunk_every(26)
            |> Enum.reduce([], fn x, acc ->
              frame_stats = @fields
              |> Enum.zip(x)
              |> Map.new
              acc ++ [frame_stats]
            end)

            fpf_frames = Enum.count(dict_list)

            #intentionally skipping 0th frame and last 16 frames
            {_, keyframes} = Enum.reduce(1..(fpf_frames-16), {1, [0]}, fn x, acc ->
              {frame_count_so_far, keyframes} = acc

              if test_candidate_kf(dict_list, x, frame_count_so_far) do
                {1, keyframes ++ [x]}
              else
                {frame_count_so_far + 1, keyframes}
              end
            end)

            keyframes
        end
    end
  end

  defp get_second_ref_usage_thresh(frame_count_so_far) do
    adapt_upto = 32
    min_second_ref_usage_thresh = 0.085
    second_ref_usage_thresh_max_delta = 0.035
    if frame_count_so_far >= adapt_upto do
      min_second_ref_usage_thresh + second_ref_usage_thresh_max_delta
    else
      min_second_ref_usage_thresh + (frame_count_so_far / (adapt_upto - 1)) * second_ref_usage_thresh_max_delta
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
    #todo: allow user to set whether we"re testing for constant-q mode keyframe placement or not. it"s not a big difference.
    
    pcnt_intra = 1.0 - Map.get(c, "pcnt_inter")
    modified_pcnt_inter = Map.get(c, "pcnt_inter") - Map.get(c, "pcnt_neutral")
    
    second_ref_usage_thresh = get_second_ref_usage_thresh(frame_count_so_far)
    
    if not qmode or frame_count_so_far > 2 and
      Map.get(c, "pcnt_second_ref") < second_ref_usage_thresh and
      Map.get(f, "pcnt_second_ref") < second_ref_usage_thresh and
      (
        Map.get(c, "pcnt_inter") < @very_low_inter_thresh or
        (
          pcnt_intra > @min_intra_level and
          pcnt_intra > (@intra_vs_inter_thresh * modified_pcnt_inter) and
          Map.get(c, "intra_error") / double_divide_check(Map.get(c, "coded_error")) < @kf_ii_err_threshold and
          (
            abs(Map.get(p, "coded_error") - Map.get(c, "coded_error")) / double_divide_check(Map.get(c, "coded_error")) > @err_change_threshold or
            abs(Map.get(p, "intra_error") - Map.get(c, "intra_error")) / double_divide_check(Map.get(c, "intra_error")) > @err_change_threshold or
            Map.get(f, "intra_error") / double_divide_check(Map.get(f, "coded_error")) > @ii_improvement_threshold
          )
        )
      ) do

      %{boost_score: boost_score, final_i: i} = Enum.reduce_while(0..15,
        %{boost_score: 0, old_boost_score: 0, decay_accumulator: 1, final_i: 0},
        fn i, %{boost_score: boost_score, old_boost_score: old_boost_score, decay_accumulator: decay_accumulator} ->

        lnf = dict_list |> Enum.at(current_frame_index + 1 + i)
        pcnt_inter = Map.get(lnf, "pcnt_inter")

        next_iiratio = @boost_factor * Map.get(lnf, "intra_error") / double_divide_check(Map.get(lnf, "coded_error"))
        next_iiratio = min(next_iiratio, @kf_ii_max)

        #Cumulative effect of decay in prediction quality.
        new_decay_accumulator = if pcnt_inter > 0.85 do
          decay_accumulator * pcnt_inter
        else
          decay_accumulator * ((0.85 + pcnt_inter) / 2.0)
        end

        #Keep a running total.
        new_boost_score = boost_score + new_decay_accumulator * next_iiratio
        
        #Test various breakout clauses.
        if pcnt_inter < 0.05 or
          next_iiratio < 1.5 or
          (pcnt_inter - Map.get(lnf, "pcnt_neutral") < 0.20 and next_iiratio < 3.0) or
          new_boost_score - old_boost_score < 3.0 or
          Map.get(lnf, "intra_error") < 200 do
          {:halt, %{boost_score: new_boost_score, final_i: i}}
        else
          {:cont, %{boost_score: new_boost_score, old_boost_score: new_boost_score, decay_accumulator: new_decay_accumulator, final_i: i}}
        end
      end)

      #If there is tolerable prediction for at least the next 3 frames then break out else discard this potential key frame and move on
      boost_score > 30 and i > 3
    else
      false
    end
  end

  defp kf_min_dist(aom_keyframes, min_frames, total_frames) do
    if min_frames != -1 do
      aom_keyframes = aom_keyframes ++ [total_frames]
      aom_scenes = aom_keyframes
      |> Enum.zip(tl(aom_keyframes))

      {_, scenes} = aom_scenes
      |> Enum.zip(tl(aom_scenes) ++ [{nil, nil}])
      |> Enum.with_index()
      |> Enum.reduce({0, []}, fn {{{frame, next_frame}, {next_scene_frame, next_scene_next_frame}}, i}, {acc, scenes} ->
        length = next_frame - frame

        scene_frame = frame - acc
        scene_length = length + acc

        cond do
          scene_length >= min_frames -> {0, scenes ++ [{scene_frame, scene_length}]}
          length(scenes) == 0 -> {scene_length, scenes}
          true ->
            {prev_frame, prev_length} = List.last(scenes)
            if i < length(aom_scenes) - 2 do
              if prev_length < min_frames do
                {acc, (scenes |> Enum.reverse() |> tl() |> Enum.reverse()) ++ [{prev_frame, prev_length + scene_length}]}
              else
                next_scene_length = next_scene_next_frame - next_scene_frame
                if next_scene_length + scene_length < prev_length + scene_length do
                  {scene_length, scenes}
                else
                  {acc, (scenes |> Enum.reverse() |> tl() |> Enum.reverse()) ++ [{prev_frame, prev_length + scene_length}]}
                end
              end
            else
              {acc, (scenes |> Enum.reverse() |> tl() |> Enum.reverse()) ++ [{prev_frame, prev_length + scene_length}]}
            end
        end
      end)
    else
      aom_keyframes
    end
  end

  defp kf_max_dist(aom_keyframes, min_dist, max_dist, original_keyframes \\ [], tolerance \\ 5) do
    if max_dist != -1 do
      aom_keyframes
      |> Enum.zip(tl(aom_keyframes))
      |> Enum.reduce([Enum.at(aom_keyframes, 0)], fn {frame, next_frame}, acc ->

        {_, _, keyframes} = Enum.reduce_while(frame..next_frame, {frame, next_frame - frame, []}, fn _, {frame_inner, length, keyframes} ->
          cond do
            length <= max_dist -> {:halt, {frame_inner, length, keyframes}}
            length - max_dist >= max_dist ->
              candidate_kfs = original_keyframes
              |> Enum.reduce([], fn candidate_kf, acc ->
                dist = abs(frame_inner + max_dist - candidate_kf)
                if dist < tolerance, do: acc ++ [{candidate_kf, dist}], else: acc
              end)
              |> Enum.sort(fn {_, dist1}, {_, dist2} -> dist2 > dist1 end)

              new_frame = case candidate_kfs do
                [{kf, _} | _] -> kf
                _ -> frame_inner + max_dist
              end

              {:cont, {new_frame, next_frame - new_frame, keyframes ++ [new_frame]}}

            floor(length / 2) > min_dist ->
              candidate_kfs = original_keyframes
              |> Enum.reduce([], fn candidate_kf, acc ->
                dist = abs(frame_inner + floor(length / 2) - candidate_kf)
                if dist < tolerance, do: acc ++ [{candidate_kf, dist}], else: acc
              end)
              |> Enum.sort(fn {_, dist1}, {_, dist2} -> dist2 > dist1 end)

              new_frame = case candidate_kfs do
                [{kf, _} | _] -> kf
                _ -> floor(frame_inner + length / 2)
              end
              
              {:cont, {new_frame, next_frame - new_frame, keyframes ++ [new_frame]}}
            true -> {:halt, {frame_inner, length, keyframes}}
          end
        end)

        acc ++ keyframes ++ [next_frame]
      end)
    else
      aom_keyframes
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

    {frames, segments, _} = aom_keyframes
    |> Enum.zip(tl(aom_keyframes))
    |> Enum.reduce({[], %{}, 0}, fn {frame, next_frame}, acc ->
      {frames, splits, last_end} = acc

      length = next_frame - frame

      {new_frames, split_n, start} = if frame in original_keyframes do
        {frames ++ [frame], length(frames), 0}
      else
        largest = original_keyframes
        |> Enum.filter(fn x -> x < frame end)
        |> Enum.max()
        
        if largest in frames or largest < last_end do
          {frames, length(frames) - 1, frame - List.last(frames)}
        else
          {frames ++ [largest], length(frames), frame - largest}
        end
      end

      split_name = split_n |> Integer.to_string() |> String.pad_leading(5, "0")
      segment_n = length(Map.keys(splits)) |> Integer.to_string() |> String.pad_leading(5, "0")

      new_split = %{segment: "#{split_name}.mkv", start: start, frames: length}

      {new_frames, splits |> Map.put(segment_n, new_split), frame + length}
    end)

    splits = frames
    |> Enum.zip(tl(frames) ++ [total_frames])
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{frame, next_frame}, i}, acc ->
      segment_n = i
      |> Integer.to_string()
      |> String.pad_leading(5, "0")
      acc |> Map.put(segment_n, %{start: frame, length: next_frame - frame})
    end)

    {frames, splits, segments}
  end

end
