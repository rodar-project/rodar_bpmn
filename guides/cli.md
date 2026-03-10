# CLI Tools

The library provides Mix tasks for working with BPMN files from the command line.

## `mix bpmn.validate`

Validate a BPMN 2.0 XML file for structural issues:

```shell
mix bpmn.validate path/to/process.bpmn
```

Runs 9 structural validation rules on each process:

- Start/end event existence and connectivity
- Sequence flow reference integrity
- Orphan node detection
- Gateway outgoing flow counts
- Exclusive gateway default flow (warning)
- Boundary event attachment

If a collaboration element is present, cross-process constraints are also checked (participant refs, message flow refs).

Exit code 0 on clean or warnings-only, exit code 1 on errors.

## `mix bpmn.inspect`

Print the parsed structure of a BPMN file:

```shell
mix bpmn.inspect path/to/process.bpmn
```

Output includes:

- Diagram ID
- Each process with element counts grouped by type
- Element IDs for each type
- Collaboration info (participants, message flows) if present

## `mix bpmn.run`

Execute a BPMN process from an XML file:

```shell
mix bpmn.run path/to/process.bpmn
mix bpmn.run path/to/process.bpmn --data '{"username": "alice"}'
```

Starts the application, registers the first process in the file, creates an instance, and runs it. Prints the final status and context data.

The `--data` flag accepts a JSON object that is passed as initial data to the process context.
