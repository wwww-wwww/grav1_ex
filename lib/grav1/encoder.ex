defmodule Grav1.Encoder do
  use EctoEnum, type: :encoder, enums: [:aomenc, :vpxenc, :svt_av1]

  @params %{
    :aomenc => {
      [
        {"--cpu-used", %{type: :integer, oneword: true, default: 3, min: 0, max: 9}},
        {"--end-usage", %{type: :option, oneword: true, options: ["q", "cq", "vbr", "cbr"]}},
        {"--cq-level", %{type: :integer, oneword: true, default: 20, min: 0, max: 63, requires: "--end-usage", requires_values: ["q", "cq"]}}, 
        {"--target-bitrate", %{type: :integer, oneword: true, default: 500, min: 0, max: :inf, requires: "--end-usage", requires_values: ["vbr", "cbr"]}},
        {"resolution", %{type: :option, options: ["1920x1080", "1280x720", "custom"]}},
        {"--width", %{type: :integer, oneword: true, default: 1920, min: 1, max: :inf, requires: "resolution", requires_values: ["custom"]}},
        {"--height", %{type: :integer, oneword: true, default: 1080, min: 1, max: :inf, requires: "resolution", requires_values: ["custom"]}}
      ],
      [
        {"--tile-columns", %{type: :integer, oneword: true, default: 1, min: 0, max: :inf}},
        {"--tile-rows", %{type: :integer, oneword: true, default: 0, min: 0, max: :inf}},
        {"--kf-max-dist", %{type: :integer, oneword: true, default: 240, min: 0, max: :inf}},
        {"--enable-keyframe-filtering", %{type: :integer, oneword: true, default: 0, min: 0, max: 2}},
        {"--auto-alt-ref", %{type: :integer, oneword: true, default: 1, min: 0, max: 1}},
        {"--lag-in-frames", %{type: :integer, oneword: true, default: 25, min: 0, max: 35}},
        {"-b", %{type: :option, oneword: false, options: ["8", "10", "12"]}}
      ]
    },
    :vpxenc => {
      [],
      []
    },
    :svt_av1 => {
      [],
      []
    }
  }

  def params() do
    @params
  end
end
