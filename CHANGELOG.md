# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Diagram.load/2` accepts a `:handler_map` option to inject handler modules into service task elements at parse time
- `Activity.Task.Service` falls back to `TaskRegistry` lookup by task ID when no inline `:handler` attribute is present

## [1.0.6] - 2026-03-11

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

- Token-based execution model with UUID tracking and execution history (`RodarBpmn`, `RodarBpmn.Token`)
- GenServer-based context/state management (`RodarBpmn.Context`)
- Process lifecycle management with suspend/resume/dehydrate/rehydrate (`RodarBpmn.Process`)
- Versioned process definition registry with deprecation support (`RodarBpmn.Registry`)
- Process instance migration between definition versions (`RodarBpmn.Migration`)
- BPMN node handlers: exclusive, parallel, inclusive, complex, and event-based gateways
- BPMN node handlers: user, script, service, send, receive, and manual tasks
- BPMN node handlers: embedded subprocess and call activity
- Event system: start, end, intermediate throw/catch, and boundary events
- Event bus with registry-based pub/sub and message correlation keys (`RodarBpmn.Event.Bus`)
- Timer support with ISO 8601 duration/cycle parsing (`RodarBpmn.Event.Timer`)
- Signal/message-triggered start events (`RodarBpmn.Event.Start.Trigger`)
- Conditional events with context subscription (`RodarBpmn.Event.Boundary`, `RodarBpmn.Event.Intermediate.Catch`)
- Compensation handling with reverse-order execution (`RodarBpmn.Compensation`)
- Sandboxed Elixir expression evaluator with AST allowlist (`RodarBpmn.Expression.Sandbox`)
- FEEL expression language support with NimbleParsec parser and tree-walking evaluator
- 18 built-in FEEL functions (numeric, string, boolean, null)
- Persistence behaviour with ETS adapter and auto-dehydration support
- Telemetry integration with span-based instrumentation and default log handler
- Observability APIs: running/waiting instances, execution history, health checks
- Structural validation with 9 rules and collaboration validation (`RodarBpmn.Validation`)
- Multi-participant orchestration via collaboration (`RodarBpmn.Collaboration`)
- BPMN 2.0 XML parser via erlsom (`RodarBpmn.Engine.Diagram`)
- BPMN 2.0 XML export with deterministic output (`RodarBpmn.Engine.Diagram.Export`)
- Custom task handler behaviour and registry (`RodarBpmn.TaskHandler`, `RodarBpmn.TaskRegistry`)
- Per-context hook system for observational callbacks (`RodarBpmn.Hooks`)
- CLI mix tasks: `rodar_bpmn.validate`, `rodar_bpmn.inspect`, `rodar_bpmn.run`, `rodar_bpmn.export`
- BPMN conformance tests for MIWG parsing and 12 execution patterns
- Comprehensive documentation with 7 guides and ExDoc integration
- CI workflow with Dialyzer, Credo, and test coverage

### Changed

- Forked from [hashiru-bpmn](https://github.com/Around25/bpmn) by [Around25](https://around25.com)
- Modernized for Elixir 1.16+ and OTP 27
- Adopted Elixir snake_case naming conventions throughout
- Renamed package from `bpmn` to `rodar_bpmn`
- Standardized diagram parser on atom keys
- Replaced Node.js script task backend with native Elixir evaluation
