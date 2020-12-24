defmodule Grav1.Encoder do
  use EctoEnum, type: :encoder, enums: [:aomenc, :vpxenc, :svt_av1]

  @params %{
    :aomenc => [
      General: [
        {
          "--cpu-used",
          "Speed setting (0..6 in good mode, 6..9 in realtime mode)",
          %{type: :integer, oneword: true, default: 3, min: 0, max: 9},
          false,
          true
        },
        {
          "Resolution",
          "Resolution",
          %{type: :option, options: ["1920x1080", "1280x720", "custom"]},
          false,
          true
        },
        {
          "--width",
          "Frame width",
          %{type: :integer, oneword: true, default: 1920, min: 1, max: :inf, requires: "Resolution", requires_values: ["custom"]},
          false,
          true
        },
        {
          "--height",
          "Frame height",
          %{type: :integer, oneword: true, default: 1080, min: 1, max: :inf, requires: "Resolution", requires_values: ["custom"]},
          false,
          true
        },
        {
          "-b",
          "Bit depth",
          %{type: :option, oneword: false, options: ["8", "10", "12"]},
          false,
          true
        }
      ],
      "Rate Control": [
        {
          "--end-usage",
          "Rate control mode",
          %{type: :option, oneword: true, options: ["q", "cq", "vbr", "cbr"]},
          false,
          true
        },
        {
          "--cq-level",
          "Constant/Constrained Quality level",
          %{type: :integer, oneword: true, default: 20, min: 0, max: 63, requires: "--end-usage", requires_values: ["q", "cq"]},
          false,
          true
        }, 
        {
          "--target-bitrate",
          "Bitrate (kbps)",
          %{type: :integer, oneword: true, default: 500, min: 0, max: :inf, requires: "--end-usage", requires_values: ["vbr", "cbr"]},
          false,
          true
        },
      ],
      "Keyframe Placement": [
        {
          "--kf-max-dist",
          "Maximum keyframe interval (frames)",
          %{type: :integer, oneword: true, default: 240, min: 0, max: :inf},
          true,
          true
        },
        {
          "--disable-kf",
          "Disable keyframe placement",
          %{type: :flag},
          false,
          false
        }
      ],
      Other: [
        {
          "--tile-columns",
          "Number of tile columns to use, log2",
          %{type: :integer, oneword: true, default: 1, min: 0, max: 6},
          true,
          true
        },
        {
          "--tile-rows",
          "Number of tile rows to use, log2",
          %{type: :integer, oneword: true, default: 0, min: 0, max: 4},
          true,
          false
        },
        {
          "--enable-keyframe-filtering",
          "Apply temporal filtering on key frame (0: no filter, 1: filter without overlay (default), 2: filter with overlay)",
          %{type: :integer, oneword: true, default: 0, min: 0, max: 2},
          true,
          true
        },
        {
          "--auto-alt-ref",
          "Enable automatic alt reference frames",
          %{type: :integer, oneword: true, default: 1, min: 0, max: 1},
          true,
          false
        },
        {
          "--lag-in-frames",
          "Max number of frames to lag",
          %{type: :integer, oneword: true, default: 25, min: 0, max: 35},
          true,
          true
        },
      ]
    ],
    :vpxenc => [
      General: [
        {
          "--cpu-used",
          "Speed setting",
          %{type: :integer, oneword: true, default: 0, min: -9, max: 9},
          false,
          true
        },
        {
          "Resolution",
          "Resolution",
          %{type: :option, options: ["1920x1080", "1280x720", "custom"]},
          false,
          true
        },
        {
          "--width",
          "Frame width",
          %{type: :integer, oneword: true, default: 1920, min: 1, max: :inf, requires: "Resolution", requires_values: ["custom"]},
          false,
          true
        },
        {
          "--height",
          "Frame height",
          %{type: :integer, oneword: true, default: 1080, min: 1, max: :inf, requires: "Resolution", requires_values: ["custom"]},
          false,
          true
        },
        {
          "-b",
          "Bit depth",
          %{type: :option, oneword: false, options: ["8", "10", "12"], overrides: %{"10" => ["--profile=2"], "12" => ["--profile=2"]}},
          false,
          true
        }
      ],
      "Rate Control": [
        {
          "--end-usage",
          "Rate control mode",
          %{type: :option, oneword: true, options: ["q", "cq", "vbr", "cbr"]},
          false,
          true
        },
        {
          "--cq-level",
          "Constant/Constrained Quality level",
          %{type: :integer, oneword: true, default: 20, min: 0, max: 63, requires: "--end-usage", requires_values: ["q", "cq"]},
          false,
          true
        }, 
        {
          "--target-bitrate",
          "Bitrate (kbps)",
          %{type: :integer, oneword: true, default: 500, min: 0, max: :inf, requires: "--end-usage", requires_values: ["vbr", "cbr"]},
          false,
          true
        },
      ],
      "Keyframe Placement": [
        {
          "--kf-max-dist",
          "Maximum keyframe interval (frames)",
          %{type: :integer, oneword: true, default: 240, min: 0, max: :inf},
          true,
          true
        },
        {
          "--disable-kf",
          "Disable keyframe placement",
          %{type: :flag},
          false,
          false
        }
      ],
      Other: [
        {
          "--tile-columns",
          "Number of tile columns to use, log2",
          %{type: :integer, oneword: true, default: 1, min: 0, max: 6},
          true,
          true
        },
        {
          "--tile-rows",
          "Number of tile rows to use, log2",
          %{type: :integer, oneword: true, default: 0, min: 0, max: 4},
          true,
          false
        },
        {
          "--auto-alt-ref",
          "Enable automatic alt reference frames, 2+ enables multi-layer.",
          %{type: :integer, oneword: true, default: 1, min: 0, max: 6},
          true,
          false
        },
        {
          "--lag-in-frames",
          "Max number of frames to lag",
          %{type: :integer, oneword: true, default: 25, min: 0, max: 25},
          true,
          true
        },
      ]
    ],
    :svt_av1 => [
      General: [
        {
          "--preset",
          "Encoder mode/Preset used",
          %{type: :integer, oneword: false, default: 0, min: -2, max: 8},
          false,
          true
        },
        {
          "Resolution",
          "Resolution",
          %{type: :option, options: ["1920x1080", "1280x720", "custom"]},
          false,
          true
        },
        {
          "--width",
          "Frame width",
          %{type: :integer, oneword: false, default: 1920, min: 1, max: :inf, requires: "Resolution", requires_values: ["custom"]},
          false,
          true
        },
        {
          "--height",
          "Frame height",
          %{type: :integer, oneword: false, default: 1080, min: 1, max: :inf, requires: "Resolution", requires_values: ["custom"]},
          false,
          true
        },
      ],
      "Rate Control": [
        {
          "--rc",
          "Rate control mode (0: CQP, 1: VBR, 2: CBR)",
          %{type: :option, oneword: false, options: ["0", "1", "2"]},
          false,
          true
        },
        {
          "--qp",
          "Constant/Constrained Quality level",
          %{type: :integer, oneword: false, default: 20, min: 0, max: 63, requires: "--rc", requires_values: ["0"]},
          false,
          true
        },
        {
          "--tbr",
          "Target bitrate (kbps)",
          %{type: :integer, oneword: false, default: 20, min: 0, max: 63, requires: "--rc", requires_values: ["1", "2"]},
          false,
          true
        },
      ],
      #"Keyframe Placement" => [
      #  {
      #    "--keyint",
      #    "Intra period interval(frames) (-2: default intra period , -1: No intra update or [0-255])",
      #    %{type: :integer, oneword: false, default: 240, min: 0, max: :inf}
      #  },
      #],
      Other: [
        {
          "--tile-columns",
          "Number of tile columns to use, log2",
          %{type: :integer, oneword: false, default: 1, min: 0, max: 6},
          true,
          true
        },
        {
          "--tile-rows",
          "Number of tile rows to use, log2",
          %{type: :integer, oneword: false, default: 0, min: 0, max: 4},
          true,
          false
        },
      ]
    ]
  }
  |> Enum.map(fn {enc, cat} ->
    new_cat =
      cat
      |> Enum.map(fn {cat_name, params} ->
        new_params =
          params
          |> Enum.map(fn {a, b, c, d, e} ->
            %{name: a, desc: b, data: c, optional: d, enabled: e}
          end)

        {cat_name, new_params}
      end)

    {enc, new_cat}
  end)
  |> Map.new()
  
  @params_json Enum.map(@params, fn {enc, cat} ->
      all_params =
        cat
        |> Enum.reduce(%{}, fn {_, params}, acc ->
          params = params |> Enum.reduce(%{}, fn param, acc2 ->
            Map.put(acc2, param.name, param)
          end)
          Map.merge(acc, params)
        end)
  
      {enc, all_params}
    end)
    |> Map.new()
    |> Jason.encode!(@params)
  
  def params_json() do
    @params_json
  end

  def params() do
    @params
  end
end
