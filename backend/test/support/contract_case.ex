defmodule Dunda.ContractCase do
  @moduledoc """
  API-contract test helper: validates a live controller-test JSON response
  against the schema declared for its operation in
  `priv/openapi/dunda.json` — the authoritative, hand-maintained contract
  for the JSON API surface (see that file's `info.description`).

  Usage (inside an existing controller test, alongside its normal
  assertions — this does not replace them):

      import Dunda.ContractCase

      conn = get(conn, "/api/events")
      assert %{"data" => _} = json_response(conn, 200)
      assert_matches_contract("listEvents", 200, json_response(conn, 200))

  Note for reviewers: this module depends on `ex_json_schema`'s public API
  (`ExJsonSchema.Schema.resolve/1`, `ExJsonSchema.Validator.validate_fragment/3`)
  exactly as documented for that library. This sandbox has no Elixir
  toolchain available to execute and confirm it end-to-end — run
  `mix test test/dunda_web/contract` first after `mix deps.get` to confirm
  before relying on it elsewhere.
  """

  @spec_path Path.join([__DIR__, "..", "..", "priv", "openapi", "dunda.json"])

  @doc "Raw, unresolved OpenAPI document (for manual paths/responses navigation)."
  def raw_spec do
    @spec_path
    |> File.read!()
    |> Jason.decode!()
  end

  @doc "The document resolved for JSON Schema `$ref` lookups against `components/schemas/*`."
  def resolved_spec do
    raw_spec() |> ExJsonSchema.Schema.resolve()
  end

  @doc """
  Resolves `operation_id` + `status` (an OpenAPI path/method/response,
  looked up by `operationId` rather than by literal path+method so call
  sites read naturally) to the `#/components/schemas/...` ref that response
  declares, by walking the RAW (unresolved) document's `paths` map — this is
  OpenAPI-specific navigation `ex_json_schema` has no opinion about, kept
  deliberately separate from JSON-Schema `$ref` resolution proper.
  """
  def response_schema_ref(operation_id, status) do
    status_key = to_string(status)

    {_path, _method, operation} =
      raw_spec()["paths"]
      |> Enum.find_value(fn {path, methods} ->
        Enum.find_value(methods, fn {method, op} ->
          if op["operationId"] == operation_id, do: {path, method, op}
        end)
      end) || raise "no operation with operationId=#{operation_id} in dunda.json"

    response = operation["responses"][status_key] || raise "operationId=#{operation_id} has no #{status_key} response"
    response_object = deref(response, raw_spec())
    schema_ref = get_in(response_object, ["content", "application/json", "schema"])
    schema_object = deref(schema_ref, raw_spec())
    schema_object["$ref"] || raise "operationId=#{operation_id} response #{status_key} has no schema $ref"
  end

  defp deref(%{"$ref" => "#/" <> pointer}, root) do
    pointer
    |> String.split("/")
    |> Enum.reduce(root, fn segment, acc -> Map.fetch!(acc, segment) end)
  end

  defp deref(object, _root), do: object

  @doc "Asserts `data` matches the schema declared for `operation_id`'s `status` response."
  @spec assert_matches_contract(String.t(), integer(), term()) :: :ok
  def assert_matches_contract(operation_id, status, data) do
    ref = response_schema_ref(operation_id, status)

    case ExJsonSchema.Validator.validate_fragment(resolved_spec(), ref, data) do
      :ok ->
        :ok

      {:error, errors} ->
        raise ExUnit.AssertionError,
          message: "response for #{operation_id} (#{status}) does not match #{ref}:\n#{inspect(errors, pretty: true)}\n\ndata:\n#{inspect(data, pretty: true)}"
    end
  end
end
