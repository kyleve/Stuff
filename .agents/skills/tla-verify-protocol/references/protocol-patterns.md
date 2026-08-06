# Protocol modeling patterns

Use these as prompts for state discovery, not templates to copy blindly.

## Queue drain and teardown

Consider variables for lifecycle, admission, pending item identities, in-flight
work, durable retry state, waiters, callbacks, terminal outcomes, and the
resource being torn down.

Separate actions for enqueue, begin work, succeed, fail, retry, begin close,
stop the producer, drain, cancel, clear durable state, destroy the resource,
late completion, and return from close.

Typical safety properties:

- nothing is admitted after the defined cutoff;
- every accepted item is pending, in flight, or terminal exactly once;
- no callback or write reaches the resource after teardown returns;
- terminal state retains no queue, worker, waiter, callback, or retry item;
- repeated teardown is idempotent and wakes each waiter exactly once.

Typical liveness properties: teardown eventually returns, and accepted work
eventually commits or reaches its specified cancellation/drop outcome. Tie that
claim to explicit assumptions that producer stop, writes, callbacks, and flushes
eventually return.

## Serialized or coalescing worker

Consider desired input, persisted input, captured target, real side-effect
state, published output, and worker phase. Model submission, begin-effect, and
completion separately. Change desired input while an effect is in flight.

Check that quiescent output matches the latest effective intent and that the
worker eventually settles. Verify every production entry point joins the same
lane; serializing one caller while another bypasses it does not implement the
model.

## Generation token and cancellation

Track the current generation, each operation's captured generation, cancellation
request, side-effect start, and publication. Let obsolete work complete late.

Check that stale generations cannot publish or mutate current resources, that
the current generation can still progress, and that cancellation has the exact
guarantees the runtime actually provides. Do not model cancellation as immediate
termination unless production enforces that.

## Retry and durable outbox

Track item identity across volatile queue, durable mirror, active attempt,
committed set, and explicit drop outcome. Model save/load failure, retry failure,
capacity policy, relaunch, and teardown racing with an attempt.

Check no silent loss or duplicate commit, honest durability state, convergence
under stated recovery assumptions, and no replay into an erased world.

## Resource handoff and installation

Track owner, installed resource identity, waiting consumers, lifecycle/generation,
and teardown. Model early consumers, installation, replacement, cancellation,
and late use.

Check that at most one resource is authoritative, consumers never observe mixed
worlds, a handoff never creates a fallback resource, waiters resume exactly once,
and replacement invalidates stale consumers according to the contract.
