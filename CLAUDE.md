# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Elixir BPMN 2.0 execution engine (formerly "hashiru-bpmn"). Parses BPMN 2.0 XML diagrams and executes processes using a token-based flow model. Version 0.1.0-dev targeting Elixir ~> 1.16 with OTP 27+.

## Build & Test Commands

```shell
mix deps.get && mix deps.compile && mix compile   # Setup
mix test                                           # Run all tests
mix test test/bpmn/context_test.exs                # Run a single test file
mix test test/bpmn/context_test.exs:10             # Run a single test at line
mix credo                                          # Lint
mix coveralls                                      # Tests with coverage
mix docs                                           # Generate documentation
```

## Architecture

### Token-based Execution Model

All BPMN nodes implement `token_in/2` (some also `token_in/3` with `from_flow` for gateway join tracking). The main dispatcher `Bpmn` (lib/bpmn.ex) routes elements by type to handler modules and `Bpmn.release_token/2` passes tokens to the next nodes.

Return tuples: `{:ok, context}`, `{:error, msg}`, `{:manual, _}`, `{:fatal, _}`, `{:not_implemented}`.

### Key Modules

- **`Bpmn`** — Main dispatcher; pattern-matches on element type tuples like `{:bpmn_activity_task_user, %{...}}`
- **`Bpmn.Context`** — Agent-based state management with `get/2`, `put_data/3`, `get_data/2`, `put_meta/3`, `get_meta/2`, `record_token/3`, `token_count/2`, `record_activated_paths/3`, `swap_process/2`
- **`Bpmn.Expression`** — Evaluates condition expressions on sequence flows
- **`Bpmn.Engine.Diagram`** — Parses BPMN 2.0 XML via `erlsom`, returns process maps keyed by element ID
- **`Bpmn.Port.Nodejs`** — GenServer managing a Node.js child process via Erlang ports (JSON protocol with Jason)

### Module Organization

- `lib/bpmn/activity/` — Tasks (user, script, service, send, receive, manual) and subprocesses
- `lib/bpmn/event/` — Start, end, intermediate, boundary events
- `lib/bpmn/gateway/` — Exclusive, parallel, inclusive, complex, event-based gateways
- `lib/bpmn/port/` — Node.js port communication and supervisor

### Testing Conventions

Tests rely heavily on doctests embedded in module documentation. Unit tests in `test/` mirror the `lib/` structure. Test modules use `async: true` where possible.

## Commit Message Format

```
<type>(<scope>): <subject>
```

Types: `build`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `style`, `test`
Scopes: `engine`, `plugin`, `scripts`, `api`, `packaging`, `changelog`

Subject: imperative present tense, no capitalized first letter, no trailing dot.

## Branch Strategy

Feature branches off `develop`. PRs target `develop`.
