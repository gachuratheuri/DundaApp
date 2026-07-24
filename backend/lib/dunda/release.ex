defmodule Dunda.Release do
  @moduledoc "Release-safe database lifecycle operations."

  @app :dunda

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn started_repo ->
          Ecto.Migrator.run(started_repo, :up, all: true)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn started_repo ->
        Ecto.Migrator.run(started_repo, :down, to: version)
      end)
  end

  defp load_app do
    Application.load(@app)
  end
end
