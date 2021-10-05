defmodule Grav1.Encoder do
  use EctoEnum, type: :encoder, enums: [:aomenc, :vpxenc, :svt_av1]

  @default_params %{
    :aomenc => [
      {"--end-usage", "q"},
      {"--cq-level", "20"},
      {"--cpu-used", "3"},
      {"-b", "10"},
      {"--tile-columns", "1"},
      {"--enable-keyframe-filtering", "0"},
      {"--lag-in-frames", "35"}
    ],
    :vpxenc => [
      {"--end-usage", "q"},
      {"--cq-level", "20"},
      {"--cpu-used", "0"},
      {"-b", "10"},
      {"--profile", "2"},
      {"--tile-columns", "1"},
      {"--row-mt", "1"},
      {"--lag-in-frames", "25"}
    ],
    :svt_av1 => []
  }

  @encoders_json Jason.encode!(Map.keys(@default_params))

  def encoders_json() do
    @encoders_json
  end

  def default_params() do
    @default_params
    |> Enum.map(fn {enc, params} ->
      {enc,
       params
       |> Enum.reduce([], fn {k, v}, acc ->
         case k do
           "--" <> _ -> acc ++ ["#{k}=#{v}"]
           "-" <> _ -> acc ++ [k, v]
           _ -> acc ++ [k, v]
         end
       end)}
    end)
    |> Map.new()
  end
end
