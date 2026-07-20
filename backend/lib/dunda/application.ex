defmodule Dunda.Application do
  use Application

  @impl true
  def start(_type, _args) do
    topologies = [
      k8s: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: "dunda-api-headless",
          application_name: "dunda"
        ]
      ]
    ]

    # Start order is load-bearing:
    #  1. Vault     — keys available before any Ecto schema initialises
    #  2-3. Repos   — write path, then read replica
    #  4. Redix     — Redis pool before any inventory process
    #  5. Cluster   — join the cluster BEFORE Horde starts
    #  6-7. Horde   — registry must exist before the dynamic supervisor registers
    #  8-9. Payments — CRI routing registry + state-machine supervisor
    #  10. Endpoint — accept HTTP only after all data deps are healthy
    #  11. Oban     — background jobs last
    children =
      [
        Dunda.Vault,
        Dunda.Repo,
        Dunda.ReadRepo,
        Dunda.Observability,
        {Redix, Application.get_env(:dunda, :redis, []) |> Keyword.put(:name, :redix)},
        {Cluster.Supervisor, [topologies, [name: Dunda.ClusterSupervisor]]},
        {Horde.Registry, [name: Dunda.InventoryRegistry, keys: :unique, members: :auto]},
        {Horde.DynamicSupervisor,
         [name: Dunda.InventorySupervisor, strategy: :one_for_one, members: :auto]}
      ] ++
        Dunda.Payments.child_specs() ++
        [
          # Scraper Bloom pre-filter — must exist before Oban runs ingest jobs.
          Dunda.Scraper.Dedup,
          {Phoenix.PubSub, name: Dunda.PubSub},
          DundaWeb.Endpoint,
          Supervisor.child_spec({Oban, Application.fetch_env!(:dunda, Oban)}, shutdown: 30_000)
        ]

    opts = [strategy: :one_for_one, name: Dunda.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DundaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
