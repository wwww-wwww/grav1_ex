defmodule Grav1Web.PageView do
  use Grav1Web, :view

  alias Grav1.Guardian

  alias Phoenix.HTML.{Tag, Form}

  def logged_in?(conn) do
    Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil
  end

  def encoders_json() do
    Grav1.Encoder.params()
    |> Enum.map(fn {a, b} ->
      b =
        b
        |> Tuple.to_list()
        |> List.flatten()
        |> Map.new()

      {a, b}
    end)
    |> Map.new()
    |> Jason.encode!()
  end

  def render_encoder_param(encoder, param_name, param) do
    case param do
      %{type: :integer, default: default, min: min, max: max} ->
        Tag.tag(:input,
          id: "opt_#{encoder}_#{param_name}",
          type: :number,
          value: default,
          min: min,
          max: max,
          class: "param"
        )

      %{type: :option, options: options} ->
        Form.select(nil, "#{param_name}", options,
          id: "opt_#{encoder}_#{param_name}",
          class: "param"
        )

      _ ->
        "?"
    end
  end
end
