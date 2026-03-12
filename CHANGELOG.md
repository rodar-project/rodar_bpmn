# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `mix rodar.scaffold` mix task — generates handler module stubs from a BPMN file with correct behaviours and callbacks
- `Rodar.Scaffold` module — core scaffolding logic for task extraction and handler code generation
- `Rodar.Scaffold.Discovery` module — convention-based handler auto-discovery at `<AppName>.Workflow.<BpmnFilename>.Handlers.<TaskName>` paths (namespace configurable via `config :rodar, :scaffold_namespace`)
- `Scaffold.bpmn_base_name/1` and `Scaffold.default_module_prefix/2` — shared naming helpers for scaffold and discovery
- `Diagram.load/2` now accepts `:bpmn_file`, `:app_name`, and `:discover_handlers` options for automatic handler discovery at parse time
- `mix rodar.run` automatically discovers scaffolded handlers and prints discovered vs passthrough status

### Changed

- `mix rodar.run` hook output now prints each node's own result instead of propagated downstream results — nodes that forwarded the token show `[OK]` even when a later node fails
- Handler convention path changed from `Bpmn.Handlers.<File>` to `Workflow.<File>.Handlers` (folder: `workflow/<file>/handlers/`), with namespace configurable via `config :rodar, :scaffold_namespace`

### Fixed

- Script task language resolution now checks `:scriptFormat` attribute (standard BPMN 2.0) in addition to `:type`, defaulting to `"elixir"` when neither is present — script tasks no longer return `{:not_implemented}` when only `scriptFormat` is set

## [1.3.0] - 2026-03-12

### Added

- BPMN lane support — parser extracts `laneSet`/`lane`/`childLaneSet`/`flowNodeRef` into process attrs (`:lane_set` key)
- `Rodar.Lane` module — stateless query API: `find_lane_for_node/2`, `node_lane_map/1`, `all_lanes/1`
- Lane XML export with full round-trip fidelity (including nested child lane sets)
- `Rodar.Validation.validate_lanes/2` — lane referential integrity checks (`:lane_flow_node_ref`, `:lane_duplicate_ref`)

## [1.2.0] - 2026-03-11

### Added

- `usage-rules.md` — package-level usage rules file with GOOD/BAD code examples for AI agents, included in hex package

### Fixed

- Execution history now correctly classifies preceding nodes as `:ok` when a downstream node suspends (e.g., user task returning `{:manual, _}`). Previously all nodes in the chain were recorded with the propagated downstream result instead of their own

## [1.1.0] - 2026-03-11

### Changed

- Replace `VERSION` file with inline version in `mix.exs` as the single source of truth
- Extract release tooling to `rodar_release` package — release command is now `mix rodar_release`
- Bump type now controls the release version (decided at release time) instead of the next dev version
- Remove `-dev` suffix convention from versioning workflow

### Removed

- `VERSION` file — no longer needed
- `Mix.Tasks.Rodar.Release` — replaced by `mix rodar_release` from the `rodar_release` package

## [1.0.8] - 2026-03-11

### Added

- `Rodar.Expression.ScriptEngine` behaviour and `Rodar.Expression.ScriptRegistry` for pluggable script language support in script tasks
- `Diagram.load/2` accepts a `:handler_map` option to inject handler modules into service task elements at parse time
- `Activity.Task.Service` falls back to `TaskRegistry` lookup by task ID when no inline `:handler` attribute is present

## [1.0.7] - 2026-03-11

### Changed

- Update repository URLs from rodar-bpmn to rodar

## [1.0.6] - 2026-03-11

### Changed

- Update repository URLs to rodar-project organization
- Moved Roadmap to parent folder

## [1.0.5] - 2026-03-11

### Added

- GitHub Actions workflow to deploy ExDoc documentation to GitHub Pages on push to main

### Changed

- Update installation instructions to use GitHub repository instead of Hex.pm
- Update homepage URL in mix.exs to point to GitHub Pages documentation

## [1.0.4] - 2026-03-11

### Changed

- Clarify versioning and release workflow documentation in CLAUDE.md, README.md, and CONTRIBUTING.md with concrete examples and step-by-step guide

## [1.0.0] - 2026-03-10

### Added

- Token-based execution model with UUID tracking and execution history (`Rodar`, `Rodar.Token`)
- GenServer-based context/state management (`Rodar.Context`)
- Process lifecycle management with suspend/resume/dehydrate/rehydrate (`Rodar.Process`)
- Versioned process definition registry with deprecation support (`Rodar.Registry`)
- Process instance migration between definition versions (`Rodar.Migration`)
- BPMN node handlers: exclusive, parallel, inclusive, complex, and event-based gateways
- BPMN node handlers: user, script, service, send, receive, and manual tasks
- BPMN node handlers: embedded subprocess and call activity
- Event system: start, end, intermediate throw/catch, and boundary events
- Event bus with registry-based pub/sub and message correlation keys (`Rodar.Event.Bus`)
- Timer support with ISO 8601 duration/cycle parsing (`Rodar.Event.Timer`)
- Signal/message-triggered start events (`Rodar.Event.Start.Trigger`)
- Conditional events with context subscription (`Rodar.Event.Boundary`, `Rodar.Event.Intermediate.Catch`)
- Compensation handling with reverse-order execution (`Rodar.Compensation`)
- Sandboxed Elixir expression evaluator with AST allowlist (`Rodar.Expression.Sandbox`)
- FEEL expression language support with NimbleParsec parser and tree-walking evaluator
- 18 built-in FEEL functions (numeric, string, boolean, null)
- Persistence behaviour with ETS adapter and auto-dehydration support
- Telemetry integration with span-based instrumentation and default log handler
- Observability APIs: running/waiting instances, execution history, health checks
- Structural validation with 9 rules and collaboration validation (`Rodar.Validation`)
- Multi-participant orchestration via collaboration (`Rodar.Collaboration`)
- BPMN 2.0 XML parser via erlsom (`Rodar.Engine.Diagram`)
- BPMN 2.0 XML export with deterministic output (`Rodar.Engine.Diagram.Export`)
- Custom task handler behaviour and registry (`Rodar.TaskHandler`, `Rodar.TaskRegistry`)
- Per-context hook system for observational callbacks (`Rodar.Hooks`)
- CLI mix tasks: `rodar.validate`, `rodar.inspect`, `rodar.run`, `rodar.export`
- BPMN conformance tests for MIWG parsing and 12 execution patterns
- Comprehensive documentation with 7 guides and ExDoc integration
- CI workflow with Dialyzer, Credo, and test coverage

### Changed

- Forked from [hashiru-bpmn](https://github.com/Around25/bpmn) by [Around25](https://around25.com)
- Modernized for Elixir 1.16+ and OTP 27
- Adopted Elixir snake_case naming conventions throughout
- Renamed package from `bpmn` to `rodar`
- Standardized diagram parser on atom keys
- Replaced Node.js script task backend with native Elixir evaluation
