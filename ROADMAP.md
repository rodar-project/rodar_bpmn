# Roadmap

This roadmap outlines the planned enhancements for the BPMN execution engine, organized into phases. Each phase builds on the previous one to incrementally deliver a fully functional, production-grade engine.

## Phase 1: Foundation Fixes

Fix critical issues that prevent the engine from working end-to-end.

- [x] **Fix atom/string key mismatch** — The diagram parser (`Bpmn.Engine.Diagram`) produces string keys (`"outgoing"`, `"id"`) but `Bpmn.Event.Start` pattern-matches on atom keys (`:outgoing`). Standardize on one convention across the entire codebase.
- [x] **Fix Node.js port hardcoded path** — `Bpmn.Port.Nodejs` defaults to `/Users/cosmin/Incubator/...`. Use `Application.app_dir/2` or application config.
- [x] **Adopt Elixir naming conventions** — Rename `releaseToken/2` to `release_token/2`, `tokenIn/2` to `token_in/2`, `tokenOut/2` to `token_out/2`, `initData` to `init_data`, etc.
- [x] **Add typespecs** — Define `@type` for node tuples, context state, and result tuples. Add `@spec` to all public functions.
- [x] **Add an end-to-end integration test** — Load `user_login.bpmn`, create a context, execute, and assert the result. This becomes the regression baseline for all future work.

## Phase 2: Modernize Dependencies and Tooling

Bring the project up to current Elixir standards.

- [x] **Update Elixir version requirement** — Bump from `~> 1.5` to `~> 1.16` or later.
- [x] **Replace deprecated patterns** — Remove `Supervisor.Spec`, use child spec tuples. Replace `use Mix.Config` with `import Config`.
- [x] **Replace Poison with Jason** — Jason is the community standard and significantly faster.
- [x] **Update Credo, ExDoc, ExCoveralls** to current versions.
- [x] **Add Dialyzer** — Add `dialyxir` as a dev dependency and fix all warnings.
- [x] **Set up CI** — Replace the Travis CI badge/config with GitHub Actions. Run `mix test`, `mix credo`, `mix dialyzer` on every PR.

## Phase 3: Core Node Implementations

Implement the stub modules to support real process execution.

### Events

- [x] **End Event** — Mark the process path as completed. Handle event definitions: error (set error state in context), terminate (stop all parallel branches), and plain end (normal completion).
- [x] **Intermediate Throw Event** — Emit signals/messages/escalations into the event system.
- [x] **Intermediate Catch Event** — Pause execution and wait for an external event (timer, message, signal).
- [x] **Boundary Event** — Attach to tasks. Supports error, message, signal, timer, and escalation event types.

### Gateways

- [x] **Exclusive Gateway** — Evaluate conditions on all outgoing sequence flows, route the token down the first matching path (or the default flow).
- [x] **Parallel Gateway** — Fork: release tokens to all outgoing flows concurrently. Join: wait until tokens arrive on all incoming flows before continuing.
- [x] **Inclusive Gateway** — Fork: release tokens to all outgoing flows whose conditions evaluate to true. Join: synchronize all activated incoming paths.
- [x] **Complex Gateway** — Support custom activation rules with expression-based join conditions.
- [x] **Event-Based Gateway** — Wait for one of several events and route based on which fires first.

### Tasks

- [x] **Script Task** — Complete the implementation. Execute the script via sandboxed Elixir evaluator, write results back to the context, and release the token to outgoing flows.
- [x] **Service Task** — Define a behaviour/callback module that users implement. The engine invokes it, passing context data, and writes results back.
- [x] **User Task** — Pause execution and return `{:manual, task_data}`. Provide a `resume/3` API to continue execution after external input is received.
- [x] **Send Task** — Emit a message into the event system.
- [x] **Receive Task** — Pause execution and wait for a matching message.
- [x] **Manual Task** — Similar to user task but with no engine interaction expected. Pause and wait for external completion signal.

### Subprocesses

- [x] **Embedded Subprocess** — Execute a nested set of elements within the parent process context.
- [x] **Call Activity** — Reference and execute an external process definition by ID via `Bpmn.Registry`.

## Phase 4: Execution Engine Improvements

Enhance the execution runtime for correctness and reliability.

- [x] **Token model** — Introduce a token struct with an ID, current node, state (active/completed/waiting), and parent token (for subprocess tracking). Replace the implicit "token as function call" model.
- [x] **Process registry** — Implement the registry described in `Bpmn` moduledoc. Register loaded process definitions by ID so any node can look them up at runtime. Use Elixir's built-in `Registry` module.
- [x] **Process lifecycle** — Implement `Bpmn.Process` with `activate/1`, `suspend/1`, `resume/1`, `terminate/1`. Track process instance state (created, running, suspended, completed, terminated).
- [x] **Context supervision** — Replace the plain Agent with a supervised GenServer. Handle crashes gracefully by restarting from the last known state.
- [x] **Execution history** — Record each node visit, timestamp, input data, and output data. Useful for debugging and audit trails.
- [x] **Error propagation** — Implement BPMN error handling: when an error is thrown, walk up the scope tree looking for a matching boundary error event. If none is found, propagate to the process level.
- [ ] **Compensation** — Track completed activities and their compensation handlers. When a compensate event is triggered, execute compensation in reverse completion order.

## Phase 5: Event System

Add publish/subscribe infrastructure for BPMN events.

- [x] **Event bus** — `Bpmn.Event.Bus` — Registry-based pub/sub using `Bpmn.EventRegistry` with `:duplicate` keys. Message (point-to-point), signal and escalation (broadcast).
- [x] **Message events** — Correlate incoming messages to waiting receive tasks or intermediate catch events by message name.
- [x] **Signal events** — Broadcast signals to all waiting catch events and boundary events.
- [x] **Timer events** — `Bpmn.Event.Timer` — ISO 8601 duration parsing, `Process.send_after/3` scheduling. Context handles `{:timer_fired, ...}` via `handle_info`.
- [x] **Escalation events** — Broadcast escalations to subscribing boundary events.
- [ ] **Conditional events** — Re-evaluate conditions when context data changes.
- [ ] **Message correlation keys** — Advanced routing beyond name matching.
- [x] **Timer cycle parsing** — ISO 8601 repeating intervals (`R3/PT10S`, `R/PT1M`, bare duration). Parser extracts `timeDuration`, `timeCycle`, `timeDate` from XML sub-elements.
- [ ] **Signal/message-triggered start events** — Auto-create process instances on event.

## Phase 6: Expression Engine

Replace the current `Code.eval_string` approach with something safe and extensible.

- [x] **Sandboxed expression evaluator** — `Bpmn.Expression.Sandbox` — AST-restricted Elixir evaluator. Parses via `Code.string_to_quoted`, walks AST against allowlist, evaluates safe expressions via `Code.eval_quoted`. Rejects dangerous module calls (System, File, IO, Code, Process, Port, Node).
- [x] **Parser format fix** — `Bpmn.Engine.Diagram` now emits `{:bpmn_expression, {lang, expr}}` directly (was `{:bpmn_condition_expression, %{...}}`). Backward compat maintained in `Bpmn.Expression`.
- [x] **Remove Node.js port** — Deleted `Bpmn.Port.Nodejs`, `Bpmn.Port.Supervisor`, and `priv/scripts/node.js`. Only Elixir expressions are supported.
- [x] **BPMN example expressions** — Rewrote JavaScript expressions in example BPMN files to Elixir equivalents.
- [x] **Expression testing utilities** — `Bpmn.Expression.TestHelpers` with `eval_expression/2` and `validate/1`.
- [ ] **Multi-language support** — Add support for `"feel"` (BPMN standard) expression language.

## Phase 7: Persistence and Long-Running Processes

Support processes that span hours, days, or weeks.

- [x] **State serialization** — `Bpmn.Persistence.Serializer` converts live process state into persistable snapshots. Handles MapSets (→ sorted lists), timer refs (stripped), Token structs (→ plain maps). Uses `:erlang.term_to_binary`/`binary_to_term` to preserve tuples, atoms, and complex BPMN element structures natively.
- [x] **Storage adapter behaviour** — `Bpmn.Persistence` defines the adapter callback contract (`save/2`, `load/1`, `delete/1`, `list/0`) with a facade that delegates to the configured adapter via `Application.get_env(:bpmn, :persistence)`. ETS adapter implemented (`Bpmn.Persistence.Adapter.ETS`) for development/testing.
- [x] **Dehydration/rehydration** — `Bpmn.Process.dehydrate/1` saves process state to the persistence adapter. `Bpmn.Process.rehydrate/1` restores from a snapshot: starts a new supervised context, replaces state via `Context.restore_state/2`, and re-subscribes to the event bus for active catch/boundary events. Auto-dehydrate on `{:manual, _}` is configurable via `auto_dehydrate: true|false`.
- [ ] **PostgreSQL adapter** — Production persistence backend.
- [ ] **Process migration** — Handle deploying a new version of a process definition while instances of the old version are still running.

## Phase 8: Observability and Operations

Make the engine observable and operable in production.

- [x] **Telemetry integration** — `Bpmn.Telemetry` centralizes 8 event definitions with typed helpers. `node_span/2` uses `:telemetry.span/3` for timed node execution. Token creation, process lifecycle, and event bus publish/subscribe all emit telemetry events.
- [x] **Structured logging** — `Logger.metadata` in `execute/3` (node_id, node_type, token_id) and `Bpmn.Process.init` (instance_id, process_id). `Bpmn.Telemetry.LogHandler` provides a default handler converting telemetry to structured log output.
- [x] **Dashboard data** — `Bpmn.Observability` exposes `running_instances/0`, `waiting_instances/0`, and `execution_history/1` by querying existing supervisors and registries.
- [x] **Health checks** — `Bpmn.Observability.health/0` reports supervisor_alive, process_count, context_count, registry_definitions, and event_subscriptions.

## Phase 9: BPMN Compliance and Validation

Improve spec compliance and catch errors early.

- [x] **Diagram validation** — `Bpmn.Validation` validates structural rules before execution: start/end event existence and connectivity, sequence flow ref integrity, orphan node detection, gateway outgoing counts, exclusive gateway defaults, boundary event attachment. Returns accumulated errors. Opt-in at `activate/1` via `config :bpmn, :validate_on_activate, true`.
- [x] **Multi-pool/multi-participant** — `Bpmn.Collaboration` orchestrates multi-participant collaboration diagrams. Parser handles `<bpmn:collaboration>`, `<bpmn:participant>`, `<bpmn:messageFlow>`, and `<bpmn:callActivity>`. Message flows pre-wired via `Bpmn.Event.Bus` before activation. Collaboration validation checks participant refs, message flow refs, and cross-process constraints.
- [ ] **BPMN 2.0 XML export** — Serialize a running or completed process instance back to BPMN 2.0 XML for interoperability with other tools.
- [ ] **BPMN conformance tests** — Implement test cases from the BPMN Model Interchange Working Group (MIWG) conformance test suite.

## Phase 10: Developer Experience

Make the library easy to adopt and extend.

- [x] **Task behaviour** — `Bpmn.TaskHandler` behaviour with `token_in/2` callback. `Bpmn.TaskRegistry` allows registering custom task implementations by type atom or task ID string. Lookup priority: task ID first, then type.
- [x] **Listener/hook system** — `Bpmn.Hooks` — per-context hooks for `:before_node`, `:after_node`, `:on_error`, `:on_complete`. Observational-only (cannot modify execution). Hook exceptions are caught and logged.
- [x] **Mix tasks** — `mix bpmn.validate <file>` validates structural rules, `mix bpmn.inspect <file>` prints parsed structure, `mix bpmn.run <file> [--data '{}']` executes a process.
- [ ] **LiveView dashboard** — A Phoenix LiveView component that visualizes running process instances, token positions, and execution history in real time. (Planned as separate package.)
- [x] **Documentation** — ExDoc guides for getting started, task handlers, hooks, and CLI. Module groups for organized HexDocs.
