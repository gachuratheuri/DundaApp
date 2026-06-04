defmodule Dunda.Organisations do
  @moduledoc """
  Write/read context for `Organisation` rows — the keystone that the scraper,
  the catalogue and payouts all read from.

  Writes go to the primary `Repo`; the scraper dispatcher reads through the
  replica (`ReadRepo`) since dispatch is a read-only fan-out.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Organisations.Organisation
  alias Dunda.{ReadRepo, Repo}

  @spec list_organisations() :: [Organisation.t()]
  def list_organisations do
    Organisation |> from(order_by: [asc: :name]) |> ReadRepo.all()
  end

  @doc "Organisations that are eligible for scraping (master switch on)."
  @spec scrapable_organisations() :: [Organisation.t()]
  def scrapable_organisations do
    Organisation
    |> from(where: [scraper_enabled: true])
    |> ReadRepo.all()
  end

  @spec get_organisation(integer() | String.t()) :: Organisation.t() | nil
  def get_organisation(id), do: Repo.get(Organisation, id)

  @spec get_organisation_by_slug(String.t()) :: Organisation.t() | nil
  def get_organisation_by_slug(slug), do: Repo.get_by(Organisation, slug: slug)

  @spec create_organisation(map()) :: {:ok, Organisation.t()} | {:error, Ecto.Changeset.t()}
  def create_organisation(attrs) do
    %Organisation{}
    |> Organisation.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_organisation(Organisation.t(), map()) ::
          {:ok, Organisation.t()} | {:error, Ecto.Changeset.t()}
  def update_organisation(%Organisation{} = org, attrs) do
    org
    |> Organisation.changeset(attrs)
    |> Repo.update()
  end

  @spec change_organisation(Organisation.t(), map()) :: Ecto.Changeset.t()
  def change_organisation(%Organisation{} = org, attrs \\ %{}) do
    Organisation.changeset(org, attrs)
  end
end
