defmodule Dunda.Ticketing.ScannerAdmission do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "scanner_admissions" do
    field :admission_id, :string
    field :manifest_version, :integer
    field :protocol_version, :integer, default: 2
    field :time_step, :integer
    field :proof_nonce, :binary
    field :proof_signature, :binary
    field :request_nonce, :binary
    field :request_signature, :binary
    field :gate, :string
    field :result, :string
    field :reason, :string
    field :clock_offset_seconds, :integer
    field :observed_at, :utc_datetime
    field :coordinator_received_at, :utc_datetime
    field :uploaded_at, :utc_datetime
    belongs_to :ticket, Dunda.Ticketing.Ticket, type: :binary_id
    belongs_to :event, Dunda.Events.Event
    belongs_to :scanner_device, Dunda.Ticketing.ScannerDevice, type: :binary_id
    timestamps(updated_at: false)
  end

  def changeset(admission, attrs) do
    admission
    |> cast(attrs, [:admission_id, :ticket_id, :event_id, :scanner_device_id, :manifest_version, :protocol_version, :time_step, :proof_nonce, :proof_signature, :request_nonce, :request_signature, :gate, :result, :reason, :clock_offset_seconds, :observed_at, :coordinator_received_at, :uploaded_at])
    |> validate_required([:admission_id, :ticket_id, :event_id, :scanner_device_id, :manifest_version, :protocol_version, :time_step, :proof_nonce, :proof_signature, :request_nonce, :request_signature, :result, :observed_at, :coordinator_received_at])
    |> validate_inclusion(:protocol_version, [2])
    |> validate_inclusion(:result, ~w(admitted rejected duplicate manual_review))
    |> validate_number(:manifest_version, greater_than: 0)
    |> validate_number(:time_step, greater_than_or_equal_to: 0)
    |> validate_change(:proof_nonce, fn :proof_nonce, value -> if is_binary(value) and byte_size(value) in 16..64, do: [], else: [proof_nonce: "must be 16–64 bytes"] end)
    |> validate_change(:proof_signature, fn :proof_signature, value -> if is_binary(value) and byte_size(value) == 64, do: [], else: [proof_signature: "must be a 64-byte Ed25519 signature"] end)
    |> validate_change(:request_nonce, fn :request_nonce, value -> if is_binary(value) and byte_size(value) in 16..64, do: [], else: [request_nonce: "must be 16–64 bytes"] end)
    |> validate_change(:request_signature, fn :request_signature, value -> if is_binary(value) and byte_size(value) == 64, do: [], else: [request_signature: "must be a 64-byte Ed25519 signature"] end)
    |> assoc_constraint(:ticket)
    |> assoc_constraint(:event)
    |> assoc_constraint(:scanner_device)
    |> unique_constraint(:admission_id)
    |> unique_constraint([:ticket_id, :proof_nonce])
  end
end
