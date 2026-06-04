defmodule Dunda.Ticketing do
  @moduledoc """
  Context for issuing and managing offline-verifiable tickets.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Repo
  alias Dunda.Ticketing.Ticket
  alias Dunda.Ticketing.Entitlement

  @doc """
  Issues `count` tickets to `user` for `event` from `order`, minting a JWT for each.
  """
  def issue_tickets(order, event, user, count, tier_label \\ "GENERAL") do
    price = if order, do: div(order.amount_total, count), else: 0

    Enum.map(1..count, fn _ ->
      ticket_id = Ecto.UUID.generate()
      {jwt, _secret} = Entitlement.mint(ticket_id, claims: %{"event_id" => event.id})

      %Ticket{
        id: ticket_id,
        user_id: user.id,
        event_id: event.id,
        order_id: if(order, do: order.id, else: nil),
        tier_label: tier_label,
        price_kes: price,
        status: "valid",
        jwt: jwt
      }
      |> Repo.insert!()
    end)
  end

  @doc """
  Lists all tickets for a user, preloading the associated event.
  """
  def list_user_tickets(user_id) do
    Repo.all(
      from t in Ticket,
        where: t.user_id == ^user_id,
        preload: [:event]
    )
  end
end
