# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Elixir BPMN 2.0 execution engine (formerly "hashiru-bpmn"). Parses BPMN 2.0 XML diagrams and executes processes using a token-based flow model. Version 0.1.0-dev targeting Elixir ~> 1.16 with OTP 27+.

## Build & Test Commands

```shell
mix deps.get && mix deps.compile && mix compile   # Setup
mix test                                           # Run all tests
mix test test/rodar_bpmn/context_test.exs                # Run a single test file
mix test test/rodar_bpmn/context_test.exs:10             # Run a single test at line
mix credo                                          # Lint
mix coveralls                                      # Tests with coverage
mix docs                                           # Generate documentation
mix rodar_bpmn.validate <file>                           # Validate a BPMN file
mix rodar_bpmn.inspect <file>                            # Inspect parsed structure
mix rodar_bpmn.run <file> [--data '{}']                  # Execute a process
```

## Architecture

### Token-based Execution Model

All BPMN nodes implement `token_in/2` (some also `token_in/3` with `from_flow` for gateway join tracking). The main dispatcher `RodarBpmn` (lib/rodar_bpmn.ex) routes elements by type to handler modules via `execute/2` (simple) or `execute/3` (with `RodarBpmn.Token` tracking). `RodarBpmn.release_token/2` or `release_token/3` passes tokens to the next nodes; `/3` forks child tokens for parallel branches.

Return tuples: `{:ok, context}`, `{:error, msg}`, `{:manual, _}`, `{:fatal, _}`, `{:not_implemented}`.

### Key Modules

- **`RodarBpmn`** — Main dispatcher; `execute/2` (backward compat) and `execute/3` (with token tracking + execution history). Dispatches to handler modules via private `dispatch/2`.
- **`RodarBpmn.Token`** — Execution token struct (id, current_node, state, parent_id, created_at). `new/1` generates UUID, `fork/1` creates child tokens for parallel branches.
- **`RodarBpmn.Context`** — GenServer-based state management with `get/2`, `put_data/3`, `get_data/2`, `put_meta/3`, `get_meta/2`, `record_token/3`, `token_count/2`, `record_activated_paths/3`, `swap_process/2`, `get_state/1`, `restore_state/2`, `start_supervised/2`. Includes execution history API: `record_visit/2`, `record_completion/4`, `get_history/1`, `get_node_history/2`. Conditional subscription API: `subscribe_condition/4`, `unsubscribe_condition/2` — evaluates conditions on `put_data` and fires `{:condition_met, ...}`. Handles `{:timer_fired, ...}`, `{:timer_cycle_fired, ...}`, `{:bpmn_event, ...}`, and `{:condition_met, ...}` via `handle_info`.
- **`RodarBpmn.Registry`** — GenServer + Elixir Registry for versioned process definition storage. `register/2` (backward compat, auto-increments version), `register/3` (with opts, returns `{:ok, version}`), `lookup/1` (latest), `lookup/2` (specific version), `versions/1`, `latest_version/1`, `deprecate/2`, `unregister/1`, `list/0`. Internal state uses a version ledger per process ID.
- **`RodarBpmn.Process`** — Process lifecycle GenServer. `start_link/2`, `create_and_run/2`, `activate/1`, `suspend/1`, `resume/1`, `terminate/1`, `status/1`, `get_context/1`, `dehydrate/1`, `rehydrate/1`, `definition_version/1`, `process_id/1`, `update_definition_version/2`. Tracks `definition_version` in state. Auto-dehydrates on `{:manual, _}` when configured. Optional validation gate on activate via `config :rodar_bpmn, :validate_on_activate, true`. Versioned rehydration uses `Registry.lookup/2` when `definition_version` is in snapshot.
- **`RodarBpmn.Migration`** — Process instance migration between definition versions. `check_compatibility/2` validates active node positions against target version (node existence, outgoing flow integrity, gateway token state). `migrate/2` (or `/3` with `force: true`) suspends instance, swaps process definition via `Context.swap_process/2`, updates version tracker, resumes if previously running.
- **`RodarBpmn.Event.Bus`** — Registry-based pub/sub using `RodarBpmn.EventRegistry` (`:duplicate` keys). `subscribe/3`, `unsubscribe/2`, `publish/3` (message=point-to-point with correlation key support, signal/escalation=broadcast), `subscriptions/2`. Message correlation: subscribers/publishers include optional `correlation: %{key: ..., value: ...}` for routing to specific instances when multiple wait for the same message name.
- **`RodarBpmn.Event.Timer`** — ISO 8601 duration parsing (`parse_duration/1`), cycle parsing (`parse_cycle/1` for `R3/PT10S`, `R/PT1M`, bare durations), `schedule/4` via `Process.send_after`, `schedule_cycle/5` for repeating timers, `cancel/1`.
- **`RodarBpmn.Event.Intermediate.Throw`** — Publishes message/signal/escalation to event bus, releases token.
- **`RodarBpmn.Event.Intermediate.Catch`** — Subscribes to event bus, schedules timer, or subscribes to conditional evaluation; returns `{:manual, _}`. Fires immediately if condition is already true. Has `resume/3`.
- **`RodarBpmn.Event.Boundary`** — Full implementation: error (direct activation), message/signal/escalation (event bus), timer (scheduled), conditional (context subscription, fires on data change), compensate (passive — registration in dispatcher).
- **`RodarBpmn.Compensation`** — Tracks completed activities and their compensation handlers. `register_handler/3`, `compensate_activity/2` (targeted), `compensate_all/1` (reverse order), `remove_handlers/2` (cleanup on failure). Pre-registered in `RodarBpmn.execute/3` for activities with compensation boundary events.
- **`RodarBpmn.Expression`** — Evaluates condition expressions on sequence flows. Routes to `"elixir"` (Sandbox) or `"feel"` (FEEL) evaluator based on language tag. Accepts both `{:bpmn_expression, {lang, expr}}` and legacy `{:bpmn_condition_expression, %{...}}` formats.
- **`RodarBpmn.Expression.Sandbox`** — AST-restricted Elixir expression evaluator. Parses via `Code.string_to_quoted`, walks AST against an allowlist, evaluates safe expressions via `Code.eval_quoted`. Prevents arbitrary code execution.
- **`RodarBpmn.Expression.Feel`** — FEEL (Friendly Enough Expression Language) facade. Parses and evaluates FEEL expressions via `eval/2`. FEEL bindings receive the raw data map directly (users write `count > 5`, not `data["count"] > 5`).
- **`RodarBpmn.Expression.Feel.Parser`** — NimbleParsec-based FEEL parser producing AST tuples. Supports arithmetic, comparisons, boolean operators, paths, bracket access, if-then-else, in operator (list/range), function calls (including space-separated names like `string length`), and list literals.
- **`RodarBpmn.Expression.Feel.Evaluator`** — Tree-walking evaluator for FEEL AST. Implements null propagation, three-valued boolean logic, string concatenation via `+`, and path resolution in nested maps.
- **`RodarBpmn.Expression.Feel.Functions`** — Built-in FEEL functions: numeric (`abs`, `floor`, `ceiling`, `round`, `min`, `max`, `sum`, `count`), string (`string length`, `contains`, `starts with`, `ends with`, `upper case`, `lower case`, `substring`), boolean (`not`), null (`is null`). Null propagation for all except `is null` and `not`.
- **`RodarBpmn.Expression.TestHelpers`** — Convenience functions for evaluating expressions against sample data without a full process context, and for validating expression safety.
- **`RodarBpmn.Validation`** — Structural validation for parsed process maps. `validate/1` returns accumulated `{:ok, map} | {:error, [issue]}`. `validate!/1` raises. `validate_collaboration/2` checks participant refs and message flow refs. 9 rules covering start/end events, sequence flow refs, orphan nodes, gateway outgoing, exclusive gateway defaults, boundary attachment.
- **`RodarBpmn.Collaboration`** — Multi-participant orchestration. `start/2` registers processes, creates instances, wires message flows via event bus, activates all. `stop/1` terminates all instances. Uses existing `RodarBpmn.Event.Bus` for inter-process messaging.
- **`RodarBpmn.TaskHandler`** — Behaviour for custom task handlers. Single `token_in/2` callback matching existing handler signature.
- **`RodarBpmn.TaskRegistry`** — GenServer for task handler registrations. `register/2` (atom type or string ID → module), `unregister/1`, `lookup/1`, `list/0`. Lookup priority: task ID first, then type.
- **`RodarBpmn.Hooks`** — Per-context hook system. `register/3`, `unregister/2`, `notify/3`. Events: `:before_node`, `:after_node`, `:on_error`, `:on_complete`. Observational-only, exceptions caught.
- **`RodarBpmn.Event.Start.Trigger`** — GenServer for signal/message-triggered start events. `register/1` scans a process definition for message/signal start events and subscribes to the event bus. Auto-creates process instances via `RodarBpmn.Process.create_and_run/2` when matching events fire.
- **`RodarBpmn.Engine.Diagram`** — Parses BPMN 2.0 XML via `erlsom`, returns process maps keyed by element ID. Splits `intermediateThrowEvent` → `:bpmn_event_intermediate_throw`, `intermediateCatchEvent` → `:bpmn_event_intermediate_catch`. Emits condition expressions as `{:bpmn_expression, {lang, expr}}`. Parses `collaboration`, `participant`, `messageFlow`, and `callActivity` elements. Extracts `timeDuration`, `timeCycle`, `timeDate` from timer event definitions. `export/1` delegates to `RodarBpmn.Engine.Diagram.Export.to_xml/1`.
- **`RodarBpmn.Engine.Diagram.Export`** — IO list-based BPMN 2.0 XML builder. Inverse of `Diagram.load/1`. Exports all element types (events, gateways, tasks, sequence flows, subprocesses), event definitions, collaboration, item definitions. Strips vendor-specific attributes and `_elems`. Deterministic output with sorted attributes and element ordering (sequence flows last).
- **`RodarBpmn.Persistence`** — Behaviour defining adapter callbacks (`save/2`, `load/1`, `delete/1`, `list/0`) and facade delegating to the configured adapter. Reads config from `Application.get_env(:rodar_bpmn, :persistence)`.
- **`RodarBpmn.Persistence.Serializer`** — Converts live process state to persistable snapshots and back. Handles MapSets (→ sorted lists), timer refs (stripped), Token structs (→ plain maps). Uses `:erlang.term_to_binary`/`binary_to_term` for binary serialization.
- **`RodarBpmn.Persistence.Adapter.ETS`** — GenServer owning a named ETS table (`:rodar_bpmn_persistence`). Implements `RodarBpmn.Persistence` behaviour. Suitable for development/testing.
- **`RodarBpmn.Telemetry`** — Centralizes telemetry event definitions and helpers. `events/0` returns all event names, `node_span/2` wraps dispatch with `:telemetry.span/3`, plus typed emit functions for token, process, and event bus events.
- **`RodarBpmn.Telemetry.LogHandler`** — Default telemetry handler that logs events via `Logger`. `attach/0`/`detach/0` to manage lifecycle. Node start/stop at debug, exception at error, process start/stop at info.
- **`RodarBpmn.Observability`** — Read-only query APIs: `running_instances/0` (now includes `process_id` and `definition_version`), `waiting_instances/0`, `execution_history/1`, `instances_by_version/1` (filter by process ID, optional version), `health/0`. Queries existing supervisors and registries.

### Supervision Tree

`RodarBpmn.Application` starts: `RodarBpmn.ProcessRegistry` (Elixir Registry, `:unique`), `RodarBpmn.EventRegistry` (Elixir Registry, `:duplicate`), `RodarBpmn.Registry`, `RodarBpmn.TaskRegistry`, `RodarBpmn.ContextSupervisor` (DynamicSupervisor), `RodarBpmn.ProcessSupervisor` (DynamicSupervisor), `RodarBpmn.Event.Start.Trigger`, and conditionally the persistence adapter (e.g., `RodarBpmn.Persistence.Adapter.ETS`) if `:persistence` config is set.

### Module Organization

- `lib/rodar_bpmn/activity/` — Tasks (user, script, service, send, receive, manual) and subprocesses (embedded, call activity)
- `lib/rodar_bpmn/event/` — Start, end, intermediate (throw/catch), boundary events, event bus, timer utilities
- `lib/rodar_bpmn/gateway/` — Exclusive, parallel, inclusive, complex, event-based gateways
- `lib/rodar_bpmn/expression/` — Sandboxed Elixir evaluator, FEEL evaluator (`feel/` subdirectory), and test helpers
- `lib/rodar_bpmn/persistence/` — Persistence behaviour, serializer, and adapters (ETS)
- `lib/rodar_bpmn/telemetry/` — Telemetry event definitions, helpers, and default log handler
- `lib/rodar_bpmn/observability.ex` — Dashboard query APIs and health checks
- `lib/rodar_bpmn/engine/` — BPMN 2.0 XML parser (`diagram.ex`) and exporter (`diagram/export.ex`)
- `lib/rodar_bpmn/validation.ex` — Structural validation (9 rules + collaboration validation)
- `lib/rodar_bpmn/collaboration.ex` — Multi-pool/multi-participant orchestration

### Testing Conventions

Tests rely heavily on doctests embedded in module documentation. Unit tests in `test/` mirror the `lib/` structure. Test modules use `async: true` where possible.

### Conformance Tests

BPMN conformance tests in `test/rodar_bpmn/conformance/`:
- `parse_test.exs` — Verifies MIWG reference files (A.1.0–B.2.0) parse correctly
- `execution_test.exs` — End-to-end execution of 12 standard BPMN patterns
- `coverage_test.exs` — Element type coverage analysis against MIWG B.2.0

Fixtures: `test/fixtures/conformance/miwg/` (MIWG reference), `test/fixtures/conformance/execution/` (handcrafted patterns). Download script: `scripts/download_miwg.sh`.

## Commit Message Format

```
<type>(<scope>): <subject>
```

Types: `build`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `style`, `test`
Scopes: `engine`, `plugin`, `scripts`, `api`, `packaging`, `changelog`

Subject: imperative present tense, no capitalized first letter, no trailing dot.

## Branch Strategy

Feature branches off `develop`. PRs target `develop`.

## Agent Rules

All subagents (launched via the Agent tool) MUST follow these rules:

1. **Worktree isolation**: Always use `isolation: "worktree"` so multiple agents can work in parallel without file conflicts.
2. **Update documentation**: After making code changes, update relevant docs — CLAUDE.md (architecture, key modules), module `@moduledoc`/`@doc`, and ExDoc guides in `guides/` as needed.
3. **Pass all CI checks before committing**: Before creating a commit, run and verify all pass:
   - `mix compile --warnings-as-errors`
   - `mix test`
   - `mix credo --strict`
   - `mix dialyzer` (use 600000ms timeout)
4. **Commit at the end**: After all checks pass, commit the changes in the worktree with a properly formatted commit message (see Commit Message Format above).
