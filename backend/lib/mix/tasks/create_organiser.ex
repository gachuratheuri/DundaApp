defmodule Mix.Tasks.Dunda.CreateOrganiser do
  use Mix.Task

  @shortdoc "Creates an administrator/organiser account"

  @moduledoc """
  Creates a new organiser account with email and password.

  Usage:
      mix dunda.create_organiser --email <email> --password <password> --name <name>
  """

  alias Dunda.Accounts

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [email: :string, password: :string, name: :string]
      )

    email = opts[:email] || raise "Missing option: --email"
    password = opts[:password] || raise "Missing option: --password"
    name = opts[:name] || raise "Missing option: --name"

    attrs = %{
      email: email,
      password: password,
      name: name,
      auth_provider: "email"
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        Mix.shell().info("Successfully created organiser user: #{user.name} (#{user.email})")

      {:error, changeset} ->
        Mix.shell().error("Failed to create organiser user: #{inspect(changeset.errors)}")
    end
  end
end
