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
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
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
      {:erlsom, "~> 1.5"},
      {:nimble_parsec, "~> 1.4"},
      {:telemetry, "~> 1.2"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "DEVELOPER.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "guides/getting_started.md",
        "guides/task_handlers.md",
        "guides/hooks.md",
        "guides/cli.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [Bpmn, Bpmn.Token, Bpmn.Context, Bpmn.Process, Bpmn.Registry],
        Events: [
          Bpmn.Event.Start,
          Bpmn.Event.End,
          Bpmn.Event.Intermediate.Throw,
          Bpmn.Event.Intermediate.Catch,
          Bpmn.Event.Boundary,
          Bpmn.Event.Bus,
          Bpmn.Event.Timer
        ],
        Gateways: [
          Bpmn.Gateway.Exclusive,
          Bpmn.Gateway.Parallel,
          Bpmn.Gateway.Inclusive,
          Bpmn.Gateway.Complex,
          Bpmn.Gateway.Exclusive.Event
        ],
        Tasks: [
          Bpmn.Activity.Task.Script,
          Bpmn.Activity.Task.User,
          Bpmn.Activity.Task.Service,
          Bpmn.Activity.Task.Send,
          Bpmn.Activity.Task.Receive,
          Bpmn.Activity.Task.Manual
        ],
        Extensions: [Bpmn.TaskHandler, Bpmn.TaskRegistry, Bpmn.Hooks],
        Observability: [Bpmn.Telemetry, Bpmn.Telemetry.LogHandler, Bpmn.Observability],
        Persistence: [
          Bpmn.Persistence,
          Bpmn.Persistence.Serializer,
          Bpmn.Persistence.Adapter.ETS
        ],
        Internals: [
          Bpmn.Engine.Diagram,
          Bpmn.Engine.Diagram.Export,
          Bpmn.Expression,
          Bpmn.Expression.Sandbox,
          Bpmn.Expression.Feel,
          Bpmn.Expression.Feel.Parser,
          Bpmn.Expression.Feel.Evaluator,
          Bpmn.Expression.Feel.Functions,
          Bpmn.Validation,
          Bpmn.Collaboration,
          Bpmn.SequenceFlow
        ]
      ]
    ]
  end
end
