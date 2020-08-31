defmodule Grav1.Encoder do
  use EctoEnum, type: :encoder, enums: [:aomenc, :vpxenc]

  @params %{
    :aomenc => [
      {"cpu-used", %{type: :integer, default: 3, min: 0, max: 9}},
      {"end-usage", %{type: :option, options: ["cq", "vbr", "cbr"]}},
      {"cq-level", %{type: :integer, default: 20, min: 0, max: 63, requires: {"end-usage", "cq"}}},
      {"resolution", %{type: :option, options: ["1920x1080", "1280x720", "custom"]}},
      {"width", %{type: :integer, default: 1920, min: 1, max: :inf, requires: {"resolution", "custom"}}},
      {"height", %{type: :integer, default: 1080, min: 1, max: :inf, requires: {"resolution", "custom"}}},
      {"tile-columns", %{type: :integer, default: 1, min: 0, max: :inf}},
      {"tile-rows", %{type: :integer, default: 0, min: 0, max: :inf}},
    ],
    :vpxenc => []
  }
  
  def params() do
    @params
  end
end
