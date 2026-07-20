defmodule DundaWeb.InternalAuth do
  @moduledoc "Constant-time authentication for internal operational endpoints."

  import Plug.Conn, only: [get_req_header: 2]

  @spec authorized?(Plug.Conn.t()) :: boolean()
  def authorized?(conn) do
    configured = Application.get_env(:dunda, :metrics_token)
    supplied = List.first(get_req_header(conn, "x-metrics-token"))

    is_binary(configured) and configured != "" and is_binary(supplied) and
      byte_size(configured) == byte_size(supplied) and
      Plug.Crypto.secure_compare(configured, supplied)
  end
end
