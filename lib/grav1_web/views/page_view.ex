defmodule Grav1Web.PageView do
  use Grav1Web, :view

  alias Grav1.Guardian

  alias Phoenix.HTML.{Tag, Form}

  @bytes ~w(B KB MB GB TB PB EB ZB YB)

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

  def render_project_name(project) do
    if project.name != nil and String.length(project.name) > 0 do
      project.name
    else
      Path.basename(project.input)
    end
  end

  def render_project_progressbar(project) do
    width =
      if project.progress_num != nil and
           project.progress_den != nil and
           (project.state != :preparing or
              project.status != :source_keyframes) do
        100 * project.progress_num / project.progress_den
      else
        0
      end

    Tag.content_tag(:div, "", class: "progress_bar", style: "width: #{width}%")
  end

  def render_project_left(project) do
    case project.state do
      :preparing ->
        case project.status do
          :source_keyframes ->
            project.progress_num

          :aom_keyframes ->
            "#{project.progress_num}/#{project.progress_den}"

          :verify_split ->
            "#{project.progress_num}/#{project.progress_den}"

          status ->
            status
        end

      state ->
        total_projects = map_size(project.segments)

        incomplete_projects =
          project.segments
          |> Enum.filter(&(elem(&1, 1).filesize == 0))
          |> length()

        pct =
          (100 * project.progress_num / project.progress_den)
          |> Float.round(2)
          |> Float.to_string()

        "#{pct}% | #{project.progress_num}/#{project.progress_den} | #{incomplete_projects}/#{
          total_projects
        }"
    end
  end

  def render_project_right(project) do
    case project.state do
      :preparing ->
        project.status

      state ->
        state
    end
  end

  def tab_selected(page, component) do
    if page.component == component do
      "tab selected"
    else
      "tab"
    end
  end

  def segment_pct(segment) do
    segment.progress / segment.frames
  end

  def filesize(value) do
    {exponent, _rem} =
      (:math.log(value) / :math.log(1024))
      |> Float.floor()
      |> Float.to_string()
      |> Integer.parse()

    result =
      Float.round(value / :math.pow(1024, exponent), 2)
      |> to_string()

    {:ok, unit} = Enum.fetch(@bytes, exponent)

    result <> unit
  end
end
