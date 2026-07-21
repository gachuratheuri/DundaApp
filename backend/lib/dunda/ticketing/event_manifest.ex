defmodule Dunda.Ticketing.EventManifest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "event_manifests" do
    field :version, :integer
    field :key_id, :string
    field :payload, :map, default: %{}
    field :payload_hash, :string
    field :signature, :binary
    field :valid_from, :utc_datetime
    field :valid_until, :utc_datetime
    field :published_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :event, Dunda.Events.Event
    timestamps(updated_at: false)
  end

  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [
      :event_id,
      :version,
      :key_id,
      :payload,
      :payload_hash,
      :signature,
      :valid_from,
      :valid_until,
      :published_at,
      :revoked_at
    ])
    |> validate_required([
      :event_id,
      :version,
      :key_id,
      :payload,
      :payload_hash,
      :signature,
      :valid_from,
      :valid_until
    ])
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:key_id, min: 1, max: 128)
    |> validate_length(:payload_hash, min: 64, max: 128)
    |> validate_change(:signature, fn :signature, value ->
      if is_binary(value) and byte_size(value) > 0, do: [], else: [signature: "is required"]
    end)
    |> validate_window()
    |> assoc_constraint(:event)
    |> unique_constraint([:event_id, :version])
  end

  defp validate_window(changeset) do
    from = get_field(changeset, :valid_from)
    until = get_field(changeset, :valid_until)

    if match?(%DateTime{}, from) and match?(%DateTime{}, until) and
         DateTime.compare(until, from) != :gt,
       do: add_error(changeset, :valid_until, "must be after valid_from"),
       else: changeset
  end
end
