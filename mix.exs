defmodule Bpmn.MixProject do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :bpmn,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      description: "A BPMN engine for elixir",

      # Docs
      name: "Rodar BPMN",
      source_url: "https://github.com/Around25/rodar-bpmn",
      homepage_url: "https://github.com/Around25/rodar-bpmn",
      test_coverage: [tool: ExCoveralls],
      docs: docs()
    ]
  end

  defp package do
    [
      name: "bpmn",
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Cosmin Harangus"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/Around25/rodar-bpmn"}
    ]
  end

  def cli do
    [preferred_envs: [coveralls: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Bpmn.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.4"},
      {:erlsom, "~> 1.5"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "DEVELOPER.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md"]
    ]
  end
end
