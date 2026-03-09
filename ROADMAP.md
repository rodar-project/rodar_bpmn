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
- [ ] **Intermediate Throw Event** — Emit signals/messages/escalations into the event system (Phase 5).
- [ ] **Intermediate Catch Event** — Pause execution and wait for an external event (timer, message, signal).
- [ ] **Boundary Event** — Attach to tasks. Interrupting boundary events cancel the task; non-interrupting ones spawn a parallel path.

### Gateways

- [x] **Exclusive Gateway** — Evaluate conditions on all outgoing sequence flows, route the token down the first matching path (or the default flow).
- [x] **Parallel Gateway** — Fork: release tokens to all outgoing flows concurrently. Join: wait until tokens arrive on all incoming flows before continuing.
- [ ] **Inclusive Gateway** — Fork: release tokens to all outgoing flows whose conditions evaluate to true. Join: synchronize all activated incoming paths.
- [ ] **Complex Gateway** — Support custom activation rules.
- [ ] **Event-Based Gateway** — Wait for one of several events and route based on which fires first.

### Tasks

- [x] **Script Task** — Complete the implementation. Execute the script via `Bpmn.Port.Nodejs`, write results back to the context, and release the token to outgoing flows.
- [x] **Service Task** — Define a behaviour/callback module that users implement. The engine invokes it, passing context data, and writes results back.
- [x] **User Task** — Pause execution and return `{:manual, task_data}`. Provide a `resume/3` API to continue execution after external input is received.
- [ ] **Send Task** — Emit a message into the event system.
- [ ] **Receive Task** — Pause execution and wait for a matching message.
- [ ] **Manual Task** — Similar to user task but with no engine interaction expected. Pause and wait for external completion signal.

### Subprocesses

- [ ] **Embedded Subprocess** — Execute a nested set of elements within the parent process context.
- [ ] **Call Activity** — Reference and execute an external process definition by ID.

## Phase 4: Execution Engine Improvements

Enhance the execution runtime for correctness and reliability.

- [ ] **Token model** — Introduce a token struct with an ID, current node, state (active/completed/waiting), and parent token (for subprocess tracking). Replace the implicit "token as function call" model.
- [ ] **Process registry** — Implement the registry described in `Bpmn` moduledoc. Register loaded process definitions by ID so any node can look them up at runtime. Use Elixir's built-in `Registry` module.
- [ ] **Process lifecycle** — Implement `Bpmn.Process` with `activate/1`, `suspend/1`, `resume/1`, `terminate/1`. Track process instance state (created, running, suspended, completed, terminated).
- [ ] **Context supervision** — Replace the plain Agent with a supervised GenServer. Handle crashes gracefully by restarting from the last known state.
- [ ] **Execution history** — Record each node visit, timestamp, input data, and output data. Useful for debugging and audit trails.
- [ ] **Error propagation** — Implement BPMN error handling: when an error is thrown, walk up the scope tree looking for a matching boundary error event. If none is found, propagate to the process level.
- [ ] **Compensation** — Track completed activities and their compensation handlers. When a compensate event is triggered, execute compensation in reverse completion order.

## Phase 5: Event System

Add publish/subscribe infrastructure for BPMN events.

- [ ] **Event bus** — A GenServer or `Registry`-based pub/sub system for message, signal, and timer events.
- [ ] **Message events** — Correlate incoming messages to waiting receive tasks or intermediate catch events by message name and correlation keys.
- [ ] **Signal events** — Broadcast signals to all waiting catch events and boundary events.
- [ ] **Timer events** — Schedule timers using `Process.send_after/3` or a library like Quantum. Support duration, date, and cycle timers.
- [ ] **Escalation events** — Route escalations up the subprocess hierarchy.
- [ ] **Conditional events** — Re-evaluate conditions when context data changes.

## Phase 6: Expression Engine

Replace the current `Code.eval_string` approach with something safe and extensible.

- [ ] **Sandboxed expression evaluator** — Remove `Code.eval_string` (arbitrary code execution risk). Options: a restricted Elixir subset parser, a FEEL (Friendly Enough Expression Language) implementation per BPMN spec, or a simple expression DSL.
- [ ] **Multi-language support** — The expression module already accepts a language parameter (`"elixir"`). Add support for `"feel"` (BPMN standard) and `"javascript"` (via the Node.js port).
- [ ] **Expression testing utilities** — Helper functions to test expressions against sample data without running a full process.

## Phase 7: Persistence and Long-Running Processes

Support processes that span hours, days, or weeks.

- [ ] **State serialization** — Define a serialization format for process instance state (context data, token positions, node metadata).
- [ ] **Storage adapter behaviour** — Define a behaviour for persistence backends. Implement an ETS adapter (for development) and a PostgreSQL adapter (for production).
- [ ] **Dehydration/rehydration** — When a process reaches a wait state (user task, receive task, timer), serialize and store its state. When the external event arrives, reload and resume.
- [ ] **Process migration** — Handle deploying a new version of a process definition while instances of the old version are still running.

## Phase 8: Observability and Operations

Make the engine observable and operable in production.

- [ ] **Telemetry integration** — Emit `:telemetry` events for node execution start/stop/error, process start/complete, token creation/consumption.
- [ ] **Structured logging** — Add consistent log metadata (process ID, instance ID, node ID, token ID) to all log messages.
- [ ] **Dashboard data** — Expose APIs to query running instances, token positions, waiting tasks, and execution history.
- [ ] **Health checks** — Report on Node.js port status, supervisor tree health, and pending timer count.

## Phase 9: BPMN Compliance and Validation

Improve spec compliance and catch errors early.

- [ ] **Diagram validation** — Before execution, validate structural rules: every start event has outgoing flows, gateways have correct incoming/outgoing counts, all sequence flow refs point to existing nodes, no orphan nodes.
- [ ] **BPMN 2.0 XML export** — Serialize a running or completed process instance back to BPMN 2.0 XML for interoperability with other tools.
- [ ] **BPMN conformance tests** — Implement test cases from the BPMN Model Interchange Working Group (MIWG) conformance test suite.
- [ ] **Multi-pool/multi-participant** — Support collaboration diagrams with message flows between pools.

## Phase 10: Developer Experience

Make the library easy to adopt and extend.

- [ ] **Task behaviour** — Define a `Bpmn.Task` behaviour with `execute/2` callback. Let users register custom task implementations by type or by task ID.
- [ ] **Listener/hook system** — Allow users to register callbacks for process events (before/after node execution, on error, on completion).
- [ ] **Mix tasks** — `mix bpmn.validate <file>` to validate a BPMN file, `mix bpmn.run <file>` to execute a process from the command line, `mix bpmn.inspect <file>` to print the parsed structure.
- [ ] **LiveView dashboard** — A Phoenix LiveView component that visualizes running process instances, token positions, and execution history in real time.
- [ ] **Documentation** — Comprehensive HexDocs with guides for each node type, examples, and architecture overview.
