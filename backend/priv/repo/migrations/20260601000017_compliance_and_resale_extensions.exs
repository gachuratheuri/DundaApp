defmodule Dunda.Repo.Migrations.ComplianceAndResaleExtensions do
  @moduledoc """
  Two lifecycle closers:

  * `data_subject_requests` — backs the Profile "ODPC Privacy Portal" (Kenya Data
    Protection Act 2019): access, rectification, and erasure requests with an
    auditable status trail and statutory due date.
  * `resale_listings` gains the buyer, the settlement timestamp, and the
    `face_value_cents` the asking price is capped against (the anti-scalping rule
    surfaced as "Price capped at face value" in the resale sheet) — enforced both
    in app logic and by a database CHECK.
  """
  use Ecto.Migration

  def change do
    create table(:data_subject_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :nilify_all)
      # Captured even for erasure, when the user row itself is later anonymised.
      add :subject_email, :string
      add :request_type, :string, null: false
      add :status, :string, null: false, default: "received"
      add :notes, :text
      add :due_by, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:data_subject_requests, [:user_id])
    create index(:data_subject_requests, [:status])

    create constraint(:data_subject_requests, :dsr_type_valid,
             check: "request_type IN ('access', 'rectification', 'erasure', 'portability', 'objection')"
           )

    create constraint(:data_subject_requests, :dsr_status_valid,
             check: "status IN ('received', 'in_progress', 'completed', 'rejected')"
           )

    alter table(:resale_listings) do
      add :buyer_id, references(:users, on_delete: :nilify_all)
      add :sold_at, :utc_datetime
      # Original purchase price; asking_price_kes must not exceed this.
      add :face_value_kes, :integer
    end

    create index(:resale_listings, [:buyer_id])

    create constraint(:resale_listings, :resale_asking_non_negative,
             check: "asking_price_kes >= 0"
           )

    create constraint(:resale_listings, :resale_price_capped_at_face_value,
             check: "face_value_kes IS NULL OR asking_price_kes <= face_value_kes"
           )
  end
end
