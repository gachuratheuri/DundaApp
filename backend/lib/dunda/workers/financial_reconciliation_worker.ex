defmodule Dunda.Workers.FinancialReconciliationWorker do
  @moduledoc "Detects confirmed/fulfilled intents without their authoritative settlement journal."
  use Oban.Worker, queue: :payments, max_attempts: 5
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.{PaymentIntent, JournalTransaction}
  alias Dunda.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      Repo.all(from p in PaymentIntent, where: p.state in ["confirmed", "fulfilled", "confirmed_late"], limit: 1_000)
      |> Enum.each(fn intent ->
        if is_nil(Repo.get_by(JournalTransaction, reference: "settlement:#{intent.id}")), do: _ = Dunda.Checkout.advance_state(intent, "manual_review", %{reason: "settlement_journal_missing"})
      end)
      :ok
    end
  end
end
