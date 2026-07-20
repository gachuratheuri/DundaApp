defmodule Dunda.Repo.Migrations.Phase11EncryptContactFields do
  use Ecto.Migration

  def up do
    # Do not silently migrate plaintext checkout contact numbers. An operator
    # must encrypt/export them with the configured vault and prove the
    # backfill before this destructive schema hardening is applied — the
    # same guard used for `mpesa_phone_encrypted` in
    # `20260724000001_phase6_settlement_resale_payouts.exs`.
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM orders WHERE phone IS NOT NULL) OR
         EXISTS (SELECT 1 FROM payment_intents WHERE phone IS NOT NULL) THEN
        RAISE EXCEPTION 'plaintext checkout contact numbers require an audited vault backfill before Phase 11';
      END IF;
    END $$;
    """

    alter table(:orders) do
      add :phone_encrypted, :binary
    end

    alter table(:payment_intents) do
      add :phone_encrypted, :binary
    end

    alter table(:orders), do: remove(:phone)
    alter table(:payment_intents), do: remove(:phone)
  end
end
