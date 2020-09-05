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
        case param do
          %{requires: {req_param_name, req_param_value}} ->
            Tag.tag(:input,
              id: "opt_#{encoder}_#{param_name}",
              type: :number,
              value: default,
              min: min,
              max: max,
              class: "param",
              requires_value: Jason.encode!(req_param_value)
            )

          _ ->
            Tag.tag(:input,
              id: "opt_#{encoder}_#{param_name}",
              type: :number,
              value: default,
              min: min,
              max: max,
              class: "param"
            )
        end

      %{type: :option, options: options} ->
        case param do
          %{requires: {req_param_name, req_param_value}} ->
            Form.select(nil, "#{param_name}", options,
              id: "opt_#{encoder}_#{param_name}",
              class: "param",
              requires_value: Jason.encode!(req_param_value)
            )

          _ ->
            Form.select(nil, "#{param_name}", options,
              id: "opt_#{encoder}_#{param_name}",
              class: "param"
            )
        end

      _ ->
        "?"
    end
  end

  def render_page(socket, page) do
    case page do
      nil -> ""
      page -> page
    end
  end
end
