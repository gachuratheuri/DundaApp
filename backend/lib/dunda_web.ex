defmodule DundaWeb do
  @moduledoc """
  Entrypoint defining the web interface boundary (controllers, JSON views,
  router, channels). Use as:

      use DundaWeb, :controller
      use DundaWeb, :json
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      action_fallback DundaWeb.FallbackController
    end
  end

  def json do
    quote do
      import Phoenix.Component, only: []
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0]

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {DundaWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # NOTE: do NOT `use Phoenix.Component` here — `use Phoenix.LiveView`
      # already establishes the component context; doing it twice conflicts.
      import Phoenix.HTML
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: DundaWeb.Endpoint,
        router: DundaWeb.Router
    end
  end

  @doc "Dispatch to the appropriate `use` target."
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
