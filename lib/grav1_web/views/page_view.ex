defmodule Grav1Web.PageView do
  use Grav1Web, :view

  alias Grav1.Guardian
  
  alias Phoenix.HTML.{Tag, Form}

  def logged_in?(conn) do
    Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil
  end

  def render_encoder_param(encoder, param_name, param) do
    case param do
      %{type: :integer, default: default, min: min, max: max} ->
        case param do
          %{requires: {req_param_name, req_param_value}} ->
            Tag.tag(:input, id: "opt_#{encoder}_#{param_name}", type: :number, value: default, min: min, max: max, requires: "opt_#{encoder}_#{req_param_name}", requires_value: Jason.encode!(req_param_value), class: "param")
          _ ->
            Tag.tag(:input, id: "opt_#{encoder}_#{param_name}", type: :number, value: default, min: min, max: max, class: "param")
        end
      %{type: :option, options: options} ->
        case param do
          %{requires: {req_param_name, req_param_value}} ->
            Form.select(:opt, "#{encoder}_#{param_name}", options, requires: "opt_#{encoder}_#{req_param_name}", requires_value: Jason.encode!(req_param_value), class: "param")
          _ ->
            Form.select(:opt, "#{encoder}_#{param_name}", options, class: "param")
        end
      _ -> "?"
    end
  end
end
