defmodule Grav1.Split do

  def split(input, path_split, min_frames, max_frames) do
    IO.inspect("started split")
  end

  defp get_keyframes(input) do

  end

  defp get_keyframes_ebml(input) do
    
  end

  defp get_keyframes_vapoursynth(input) do
    
  end

  defp get_keyframes_ffmpeg(input) do
    
  end

  @fields [
    "frame", "weight", "intra_error", "frame_avg_wavelet_energy",
    "coded_error", "sr_coded_error", "tr_coded_error", "pcnt_inter",
    "pcnt_motion", "pcnt_second_ref", "pcnt_third_ref", "pcnt_neutral",
    "intra_skip_pct", "inactive_zone_rows", "inactive_zone_cols", "MVr",
    "mvr_abs", "MVc", "mvc_abs", "MVrv", "MVcv", "mv_in_out_count",
    "new_mv_count", "duration", "count", "raw_error_stdev"
  ]

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

  # For more documentation on the below, see https://aomedia.googlesource.com/aom/+/8ac928be918de0d502b7b492708d57ad4d817676/av1/encoder/pass2_strategy.c#1897
    
  @min_intra_level 0.25
  @boost_factor 12.5
  @intra_vs_inter_thresh 2.0
  @very_low_inter_thresh 0.05
  @kf_II_err_threshold 2.5
  @err_change_threshold 0.4
  @II_improvement_threshold 3.5
  @kf_II_max 128.0

  defp test_candidate_kf(dict_list, current_frame_index, frame_count_so_far) do
    previous_frame_dict = dict_list |> Enum.at(current_frame_index - 1)
    current_frame_dict = dict_list |> Enum.at(current_frame_index)
    future_frame_dict = dict_list |> Enum.at(current_frame_index + 1)
    
    p = previous_frame_dict
    c = current_frame_dict
    f = future_frame_dict
    
    qmode = True
    #todo: allow user to set whether we"re testing for constant-q mode keyframe placement or not. it"s not a big difference.
    
    is_keyframe = 0
    
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
          Map.get(c, "intra_error") / double_divide_check(Map.get(c, "coded_error")) < @kf_II_err_threshold and
          (
            abs(Map.get(p, "coded_error") - Map.get(c, "coded_error")) / double_divide_check(Map.get(c, "coded_error")) > @err_change_threshold or
            abs(Map.get(p, "intra_error") - Map.get(c, "intra_error")) / double_divide_check(Map.get(c, "intra_error")) > @err_change_threshold or
            Map.get(f, "intra_error") / double_divide_check(Map.get(f, "coded_error")) > @II_improvement_threshold
          )
        )
      ) do

      %{boost_score: boost_score, final_i: i} = Enum.reduce_while(0..15,
        %{boost_score: 0, old_boost_score: 0, decay_accumulator: 1, final_i: 0},
        fn i, %{boost_score: boost_score, old_boost_score: old_boost_score, decay_accumulator: decay_accumulator, final_i: final_i} ->

        lnf = dict_list |> Enum.at(current_frame_index + 1 + i)
        pcnt_inter = Map.get(lnf, "pcnt_inter")

        next_iiratio = @boost_factor * Map.get(lnf, "intra_error") / double_divide_check(Map.get(lnf, "coded_error"))

        next_iiratio = min(next_iiratio, @kf_II_max)
          
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
      False
    end
  end

  defp get_aom_keyframes(input) do
    
  end

end
