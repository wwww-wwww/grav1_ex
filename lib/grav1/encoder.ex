defmodule Grav1.Encoder do
  use EctoEnum, type: :encoder, enums: [:aomenc, :vpxenc]

  @params %{
    :aomenc => {
      [
        {"--cpu-used", %{type: :integer, default: 3, min: 0, max: 9}},
        {"--target-bitrate", %{type: :integer, default: 500, min: 0, max: :inf, requires: "--end-usage", requires_values: ["vbr", "cbr"]}},
        {"--end-usage", %{type: :option, options: ["q", "cq", "vbr", "cbr"]}},
        {"--cq-level", %{ type: :integer, default: 20, min: 0, max: 63, requires: "--end-usage", requires_values: ["q", "cq"]}},
        {"resolution", %{type: :option, options: ["1920x1080", "1280x720", "custom"]}},
        {"--width", %{type: :integer, default: 1920, min: 1, max: :inf, requires: "resolution", requires_values: ["custom"]}},
        {"--height", %{type: :integer, default: 1080, min: 1, max: :inf, requires: "resolution", requires_values: ["custom"]}},
      ],
      [
        {"--tile-columns", %{type: :integer, default: 1, min: 0, max: :inf}},
        {"--tile-rows", %{type: :integer, default: 0, min: 0, max: :inf}},
        {"--kf-max-dist", %{type: :integer, default: 240, min: 0, max: :inf}},
        {"--enable-keyframe-filtering", %{type: :integer, default: 0, min: 0, max: 2}},
        {"--auto-alt-ref", %{type: :integer, default: 1, min: 0, max: 1}},
        {"--lag-in-frames", %{type: :integer, default: 25, min: 0, max: 35}},
        {"-b", %{type: :option, options: ["8", "10", "12"]}}
      ]
    },
    :vpxenc => {
      [],
      []
    }
  }

  def params() do
    @params
  end
end
