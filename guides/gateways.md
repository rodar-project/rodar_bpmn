# Gateways

Gateways control the flow of tokens through a BPMN process, handling decisions (diverging) and synchronization (converging).

## Exclusive Gateway (XOR)

An exclusive gateway routes the token to exactly one outgoing path based on condition evaluation.

**Diverging:** evaluates conditions on outgoing sequence flows in order and routes the token to the first match. If no condition matches, the default flow is used.

**Converging:** passes the token straight through (merge point).

```elixir
# In BPMN XML, conditions are set on sequence flows:
# <sequenceFlow id="flow_yes" sourceRef="gw" targetRef="approve">
#   <conditionExpression>amount &lt; 1000</conditionExpression>
# </sequenceFlow>
#
# The gateway specifies a default flow for the fallback case:
# <exclusiveGateway id="gw" default="flow_reject" />
```

Condition expressions are evaluated by `Rodar.Expression`, which supports both FEEL and sandboxed Elixir.

## Parallel Gateway (AND)

A parallel gateway creates or synchronizes concurrent execution paths.

**Fork:** releases tokens to all outgoing flows simultaneously. The dispatcher uses `Rodar.release_token/3` to fork child tokens for each branch.

**Join:** waits until tokens have arrived on all incoming flows before releasing a single token to the outgoing flow. Token arrival is tracked via `Rodar.Context.record_token/3`.

```elixir
# Fork: one token in, N tokens out (one per outgoing flow)
# Join: N tokens in (one per incoming flow), one token out
#
# <parallelGateway id="fork" />
#   ... parallel branches ...
# <parallelGateway id="join" />
```

## Inclusive Gateway (OR)

An inclusive gateway is a hybrid of exclusive and parallel gateways.

**Fork:** evaluates conditions on all outgoing flows and releases tokens to every flow whose condition is `true`. If no conditions match, the default flow is used. The set of activated flows is recorded in context for join synchronization.

**Join:** waits for tokens from all flows that were activated at the corresponding fork. Uses `Rodar.Context.record_activated_paths/3` to track which paths need synchronization.

## Complex Gateway

A complex gateway extends the inclusive gateway with a configurable `activationCondition` expression for join behavior.

**Fork:** evaluates conditions on outgoing flows, same as an inclusive gateway.

**Join:** uses the activation condition expression to determine when enough tokens have arrived, rather than waiting for all activated paths.

## Event-Based Gateway

An event-based gateway routes the token based on which downstream event fires first. It returns `{:manual, _}` and subscribes all downstream catch events to the event bus. The first event to fire wins, cancelling all other pending subscriptions.

```elixir
# The gateway connects to intermediate catch events:
# <eventBasedGateway id="ebgw" />
# <sequenceFlow sourceRef="ebgw" targetRef="catch_message" />
# <sequenceFlow sourceRef="ebgw" targetRef="catch_timer" />
# <intermediateCatchEvent id="catch_message">...
# <intermediateCatchEvent id="catch_timer">...
```

This is useful for patterns like "wait for a response or timeout after 30 seconds."

## Next Steps

- [Expressions](expressions.md) -- FEEL and Elixir condition evaluation used by gateways
- [Events](events.md) -- Event types used with event-based gateways
- [Process Lifecycle](process_lifecycle.md) -- Instance creation and execution
