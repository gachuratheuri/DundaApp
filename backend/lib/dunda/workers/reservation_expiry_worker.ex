defmodule Dunda.Workers.ReservationExpiryWorker do
  @moduledoc "Expires only reservations whose payment state permits release."
  use Oban.Worker, queue: :inventory, max_attempts: 5
  alias Dunda.Checkout
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout), do: {:cancel, :phase_0_containment}, else: Checkout.expire_reservations()
  end
end
