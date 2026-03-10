defmodule RodarBpmn.MixProject do
  use Mix.Project

  @version "VERSION" |> File.read!() |> String.trim()

  def project do
    [
      app: :rodar_bpmn,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      description: "A BPMN engine for Elixir",

      # Docs
      name: "Rodar BPMN",
      source_url: "https://github.com/rodgco/rodar-bpmn",
      homepage_url: "https://github.com/rodgco/rodar-bpmn",
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      docs: docs()
    ]
  end

  defp package do
    [
      name: "rodar_bpmn",
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG.md", "VERSION"],
      maintainers: ["Rodrigo Couto"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/rodgco/rodar-bpmn"}
    ]
  end

  def cli do
    [preferred_envs: [coveralls: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RodarBpmn.Application, []}
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
        "CHANGELOG.md",
        "guides/getting_started.md",
        "guides/process_lifecycle.md",
        "guides/events.md",
        "guides/gateways.md",
        "guides/expressions.md",
        "guides/task_handlers.md",
        "guides/hooks.md",
        "guides/persistence.md",
        "guides/versioning.md",
        "guides/observability.md",
        "guides/cli.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          RodarBpmn,
          RodarBpmn.Token,
          RodarBpmn.Context,
          RodarBpmn.Process,
          RodarBpmn.Registry,
          RodarBpmn.Migration
        ],
        Events: [
          RodarBpmn.Event.Start,
          RodarBpmn.Event.Start.Trigger,
          RodarBpmn.Event.End,
          RodarBpmn.Event.Intermediate,
          RodarBpmn.Event.Intermediate.Throw,
          RodarBpmn.Event.Intermediate.Catch,
          RodarBpmn.Event.Boundary,
          RodarBpmn.Event.Bus,
          RodarBpmn.Event.Timer,
          RodarBpmn.Compensation
        ],
        Gateways: [
          RodarBpmn.Gateway.Exclusive,
          RodarBpmn.Gateway.Parallel,
          RodarBpmn.Gateway.Inclusive,
          RodarBpmn.Gateway.Complex,
          RodarBpmn.Gateway.Exclusive.Event
        ],
        Tasks: [
          RodarBpmn.Activity.Task.Script,
          RodarBpmn.Activity.Task.User,
          RodarBpmn.Activity.Task.Service,
          RodarBpmn.Activity.Task.Send,
          RodarBpmn.Activity.Task.Receive,
          RodarBpmn.Activity.Task.Manual
        ],
        Extensions: [RodarBpmn.TaskHandler, RodarBpmn.TaskRegistry, RodarBpmn.Hooks],
        Observability: [
          RodarBpmn.Telemetry,
          RodarBpmn.Telemetry.LogHandler,
          RodarBpmn.Observability
        ],
        Persistence: [
          RodarBpmn.Persistence,
          RodarBpmn.Persistence.Serializer,
          RodarBpmn.Persistence.Adapter.ETS
        ],
        Internals: [
          RodarBpmn.Engine.Diagram,
          RodarBpmn.Engine.Diagram.Export,
          RodarBpmn.Expression,
          RodarBpmn.Expression.Sandbox,
          RodarBpmn.Expression.Feel,
          RodarBpmn.Expression.Feel.Parser,
          RodarBpmn.Expression.Feel.Evaluator,
          RodarBpmn.Expression.Feel.Functions,
          RodarBpmn.Validation,
          RodarBpmn.Collaboration,
          RodarBpmn.SequenceFlow
        ]
      ]
    ]
  end
end
