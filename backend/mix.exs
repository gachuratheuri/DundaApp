defmodule Dunda.MixProject do
  use Mix.Project

  def project do
    [
      app: :dunda,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  # Release definition. The `build_assets/1` step compiles + digests the
  # organiser-portal assets (Tailwind minify, esbuild minify, phx.digest)
  # before the release is assembled, so the binary ships with fingerprinted
  # CSS/JS and no external CDN dependency.
  defp releases do
    [
      dunda: [
        steps: [&build_assets/1, :assemble]
      ]
    ]
  end

  defp build_assets(release) do
    Mix.Task.run("assets.deploy")
    release
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key],
      mod: {Dunda.Application, []}
    ]
  end

  defp deps do
    [
      {:horde, "~> 0.9"},
      {:libcluster, "~> 3.3"},
      {:redix, "~> 1.1"},
      {:oban, "~> 2.15"},
      {:gen_state_machine, "~> 3.0"},
      {:cloak_ecto, "~> 1.3"},
      {:bcrypt_elixir, "~> 3.0"},
      {:bloomex, "~> 1.0"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 0.20"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:floki, "~> 0.36"},
      {:bandit, "~> 1.5"},
      {:plug, "~> 1.16"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # Organiser-portal asset pipeline (Tailwind + esbuild), replacing the CDN.
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind dunda", "esbuild dunda"],
      "assets.deploy": ["tailwind dunda --minify", "esbuild dunda --minify", "phx.digest"]
    ]
  end
end
