defmodule Dunda.Ticketing.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tickets" do
    field :tier_label, :string
    field :price_kes, :integer
    field :status, :string, default: "valid"
    field :jwt, :string
    field :holder_name, :string
    field :checked_in_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :revocation_reason, :string
    field :supersedes_ticket_id, :binary_id
    field :replaced_by_ticket_id, :binary_id
    # M-Pesa transaction that paid for this ticket (nil for order/resale paths).
    field :transaction_id, :string
    field :fulfillment_key, :string
    field :ticket_batch_id, :binary_id
    field :credential_version, :integer, default: 1
    field :credential_public_key, :binary
    field :credential_valid_from, :utc_datetime
    field :credential_valid_until, :utc_datetime
    field :credential_bound_at, :utc_datetime
    field :credential_epoch, :integer, default: 0

    belongs_to :tier, Dunda.Ticketing.TicketTier
    belongs_to :transferred_from_user, Dunda.Accounts.User, foreign_key: :transferred_from_user_id
    belongs_to :user, Dunda.Accounts.User
    belongs_to :event, Dunda.Events.Event
    belongs_to :order, Dunda.Billing.Order
    belongs_to :supersedes_ticket, __MODULE__, foreign_key: :supersedes_ticket_id
    belongs_to :replaced_by_ticket, __MODULE__, foreign_key: :replaced_by_ticket_id
    belongs_to :ticket_batch, Dunda.Checkout.TicketBatch

    has_many :scans, Dunda.Ticketing.TicketScan

    timestamps()
  end

  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :id, :tier_label, :price_kes, :status, :jwt, :user_id, :event_id, :order_id, :tier_id,
      :holder_name, :checked_in_at, :revoked_at, :revocation_reason,
      :supersedes_ticket_id, :replaced_by_ticket_id, :transferred_from_user_id,
      :transaction_id, :fulfillment_key, :ticket_batch_id, :credential_version,
      :credential_public_key, :credential_valid_from,
      :credential_valid_until, :credential_bound_at, :credential_epoch
    ])
    |> validate_required([:tier_label, :price_kes, :status, :user_id, :event_id])
    |> validate_inclusion(:status, ["valid", "transferred", "scanned", "revoked", "refunded"])
    |> validate_revocation_consistency()
    |> validate_credential_consistency()
    |> unique_constraint(:fulfillment_key, name: :tickets_fulfillment_key_index)
  end

  defp validate_revocation_consistency(changeset) do
    status = get_field(changeset, :status)
    revoked_at = get_field(changeset, :revoked_at)

    if status in ["revoked", "refunded"] and is_nil(revoked_at),
      do: add_error(changeset, :revoked_at, "is required for a revoked entitlement"),
      else: changeset
  end

  defp validate_credential_consistency(changeset) do
    version = get_field(changeset, :credential_version)
    public_key = get_field(changeset, :credential_public_key)
    from = get_field(changeset, :credential_valid_from)
    until = get_field(changeset, :credential_valid_until)
    bound_at = get_field(changeset, :credential_bound_at)

    cond do
      version not in [1, 2] -> add_error(changeset, :credential_version, "must be protocol version 1 or 2")
      version == 2 and (not is_binary(public_key) or byte_size(public_key) != 32) -> add_error(changeset, :credential_public_key, "must be a 32-byte Ed25519 public key")
      version == 2 and (is_nil(from) or is_nil(until) or DateTime.compare(until, from) != :gt) -> add_error(changeset, :credential_valid_until, "must be after credential_valid_from")
      version == 2 and is_nil(bound_at) -> add_error(changeset, :credential_bound_at, "is required for device-bound credentials")
      true -> changeset
    end
  end
end
