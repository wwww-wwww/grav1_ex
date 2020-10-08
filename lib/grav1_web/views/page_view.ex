defmodule Grav1Web.PageView do
  use Grav1Web, :view

  alias Grav1.Guardian

  alias Phoenix.HTML.{Tag, Form}

  @bytes ~w(B K M G T P E Z Y)

  def logged_in?(conn) do
    Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil
  end

  def render_encoder_param(encoder, param) do
    case param.data do
      %{type: :integer, default: default, min: min, max: max} ->
        Tag.tag(:input,
          id: "opt_#{encoder}_#{param.name}",
          type: :number,
          value: default,
          min: min,
          max: max,
          class: "param"
        )

      %{type: :flag, default: default} ->
        Tag.tag(:input,
          id: "opt_#{encoder}_#{param.name}",
          type: :checkbox,
          value: default,
          class: "param"
        )

      %{type: :option, options: options} ->
        Form.select(nil, "#{param.name}", options,
          id: "opt_#{encoder}_#{param.name}",
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
      cond do
        project.progress_num != nil and
          project.progress_den != nil and
            (project.state != :preparing or
               project.status != :source_keyframes) ->
          100 * project.progress_num / project.progress_den

        project.state == :completed ->
          100

        true ->
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

      :concatenating ->
        case project.progress_den do
          nil ->
            inspect(project.status)

          den ->
            "#{project.progress_num}/#{den} | #{project.status}"
        end

      :completed ->
        "100% | #{project.input_frames} frames"

      _ ->
        case project.progress_den do
          nil ->
            project.progress_num

          den ->
            total_segments = map_size(project.segments)

            incomplete_segments =
              project.segments
              |> Enum.filter(&(elem(&1, 1).filesize == 0))
              |> length()

            pct =
              (100 * project.progress_num / den)
              |> Float.round(2)
              |> Float.to_string()

            "#{pct}% | #{project.progress_num}/#{den} | #{incomplete_segments}/#{total_segments}"
        end
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
    Float.round(segment.progress / segment.frames * 100, 2)
  end

  def segment_desc(segment) do
    content =
      cond do
        segment.filesize > 0 ->
          filesize(segment.filesize)

        segment.verifying ->
          "verifying"

        true ->
          "#{segment.progress}/#{segment.frames}"
      end

    content_tag("div", content, class: "desc")
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
