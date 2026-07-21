defmodule Dunda.Scraper.Runs do
  @moduledoc "Best-effort durable provenance and freshness records for scraper runs."
  alias Dunda.Repo
  alias Dunda.Scraper.SourceRun

  def start(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Map.put_new(:started_at, now)
      |> Map.put_new(:metadata, %{})
      |> Map.put_new(:status, "started")

    case Repo.insert(SourceRun.changeset(%SourceRun{}, attrs)) do
      {:ok, run} -> {:ok, run}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  def finish(%SourceRun{} = run, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    run
    |> SourceRun.changeset(Map.put(attrs, :finished_at, now))
    |> Repo.update()
  rescue
    error -> {:error, error}
  end

  def record(attrs) when is_map(attrs) do
    with {:ok, run} <- start(attrs),
         {:ok, finished} <- finish(run, attrs) do
      {:ok, finished}
    end
  end
end
