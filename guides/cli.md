# CLI Tools

The library provides Mix tasks for working with BPMN files from the command line.

## `mix rodar_bpmn.validate`

Validate a BPMN 2.0 XML file for structural issues:

```shell
mix rodar_bpmn.validate path/to/process.bpmn
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

## `mix rodar_bpmn.inspect`

Print the parsed structure of a BPMN file:

```shell
mix rodar_bpmn.inspect path/to/process.bpmn
```

Output includes:

- Diagram ID
- Each process with element counts grouped by type
- Element IDs for each type
- Collaboration info (participants, message flows) if present

## `mix rodar_bpmn.run`

Execute a BPMN process from an XML file:

```shell
mix rodar_bpmn.run path/to/process.bpmn
mix rodar_bpmn.run path/to/process.bpmn --data '{"username": "alice"}'
```

Starts the application, registers the first process in the file, creates an instance, and runs it. Prints the final status and context data.

The `--data` flag accepts a JSON object that is passed as initial data to the process context.

## `mix rodar_bpmn.export`

Export a BPMN file as normalized BPMN 2.0 XML:

```shell
mix rodar_bpmn.export path/to/process.bpmn
mix rodar_bpmn.export path/to/process.bpmn --output normalized.bpmn
```

Parses the input file and re-exports it as normalized BPMN 2.0 XML. This is useful for:

- Normalizing XML formatting across different BPMN editors
- Stripping vendor-specific extensions (e.g., Camunda, Drools attributes)
- Verifying round-trip fidelity of the parser

Prints to stdout by default. Use `--output` to write to a file instead.
