defmodule Dunda.Organisations.Organisation do
  @moduledoc """
  The structural keystone of the Dunda Unified Architecture.

  A single `organisations` row simultaneously:

    * configures the scraper — the `*_id` columns are read on every cron tick by
      `Dunda.Workers.DispatchWorker.dynamic_targets_from_orgs/0`;
    * owns the events scraped/ingested under it (`events.organisation_id`);
    * holds the M-Pesa payout destination (`mpesa_phone`) used by
      `Dunda.Workers.PayoutWorker` for B2C settlements.

  Editing a row in the Organiser Portal therefore reconfigures the live system
  with no deploy and no restart.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "organisations" do
    field :name, :string
    field :slug, :string

    # Scraper source configuration. A nil/blank id means "this source is not
    # connected" and the dispatcher skips it for this org.
    field :facebook_page_id, :string
    field :instagram_account_id, :string
    field :eventbrite_org_id, :string
    field :html_scrape_url, :string

    # Master switch — when false the org is excluded from dispatch entirely.
    field :scraper_enabled, :boolean, default: true

    # B2C payout destination (Safaricom MSISDN, 2547XXXXXXXX).
    field :mpesa_phone, :string

    has_many :events, Dunda.Events.Event

    timestamps()
  end

  @sources [:facebook_page_id, :instagram_account_id, :eventbrite_org_id, :html_scrape_url]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(org, attrs) do
    org
    |> cast(attrs, [
      :name,
      :slug,
      :facebook_page_id,
      :instagram_account_id,
      :eventbrite_org_id,
      :html_scrape_url,
      :scraper_enabled,
      :mpesa_phone
    ])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &normalise_slug/1)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "lowercase letters, digits and hyphens only")
    |> validate_format(:mpesa_phone, ~r/^2547\d{8}$/,
      message: "must be a Safaricom MSISDN like 2547XXXXXXXX"
    )
    |> normalise_blanks(@sources)
    |> unique_constraint(:slug)
  end

  defp normalise_slug(nil), do: nil
  defp normalise_slug(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  # Coerce empty strings to nil so "not connected" is represented consistently.
  defp normalise_blanks(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      case get_change(acc, field) do
        "" -> put_change(acc, field, nil)
        value when is_binary(value) -> put_change(acc, field, String.trim(value))
        _ -> acc
      end
    end)
  end
end
