defmodule DundaWeb.ErrorJSON do
  @moduledoc """
  Renders generic errors for the JSON API. Phoenix calls `render/2` with a
  template name like `"404.json"` when no more specific handler exists.
  """

  def render(template, _assigns) do
    %{error: %{code: Phoenix.Controller.status_message_from_template(template)}}
  end
end
