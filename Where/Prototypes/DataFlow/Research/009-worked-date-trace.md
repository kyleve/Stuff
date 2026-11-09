# Worked trace: equal dates, copying, transformation, and persistence

Date: 2026-10-24.
Status: proposed logical records under the accepted observation contract. The record notation and implementation remain open.
Source revision: `862c573d1dd06cc7b96ed101585f85bf13857523`.
Evidence: a worked design example. No Swift compilation, instrumentation, runtime capture, or performance measurement supports this example yet.

The [observation contract](008-observation-contract.md) supplies the accepted meanings.
This example makes those meanings concrete without selecting a wire format, Swift API, identifier encoding, or generator.
Its expected records are proposals for the later experiment.

## The application fragment

```swift
func process(
    first: Date,
    second: Date,
    offset: TimeInterval,
    cutoff: Date
) throws -> Date {
    let copied = first
    let shifted = copied.addingTimeInterval(offset)

    if shifted > cutoff {
        try persist(shifted)
    }

    return second
}
```

This fragment contains no tracing annotations or tracing calls.
`persist` stands for an unspecified persistence function. Its declaration and implementation are outside this fragment.
The function returns `second` so that both independent date inputs have an observable path.

The fixture supplies four tracked inputs before the function call.
Two observed source occurrences independently supply equal dates.
Two observed configuration inputs supply the offset and cutoff.
The fixture defines these origins. Function parameter declarations do not create them.

All dates below use synthetic seconds from a common epoch.
These contents explain the example. They do not require production capture to retain raw values.

| Handle | Type | Fixture contents | Observed origin |
| --- | --- | --- | --- |
| `A` | `Date` | `1000` | First independent source occurrence |
| `B` | `Date` | `1000` | Second independent source occurrence |
| `O` | `TimeInterval` | `60` | Configuration input for the offset |
| `K` | `Date` | `1050` | Configuration input for the cutoff |

`A` and `B` have equal contents and distinct provenance handles.
These handles name trace observations. They do not invent domain identities for dates.
Existing upstream provenance must survive entry into `process`.
An unobserved upstream path requires an unavailable-ancestry marker, not a claim of independent origin.

## Logical record vocabulary

The notation below describes required information, not individual serialized events.
An implementation can combine records or emit additional diagnostics without changing these meanings.
Letters name value handles. `E1` through `E4` name operation executions. `D1` names one branch observation.
These names are local labels for this example, not an identifier allocation scheme.

| Record | Information it preserves |
| --- | --- |
| Input observation | A value handle, type, source occurrence, and ancestry status |
| Invocation and outcome | One execution, its operation site, its caller, and its observed return or error |
| Argument or return use | An execution, a role, and the existing value handle supplied in that role |
| Binding occurrence | An execution, a source site, an occurrence discriminator, and the handle bound at that site |
| Derived result | A new value handle, its producing execution, and input roles supported by an identified propagation rule |
| Branch observation | The condition handle, its observed result, the branch site, and the local execution it gates |

A binding occurrence lets the trace show a copy without creating another value version.
It also distinguishes repeated visits to the same source site.
Its representation can use an event identity or an execution, site, and sequence combination.
This example does not choose between those representations.

Argument receipt establishes participation. An identified propagation rule supplies the stronger derivation claim.
Each relationship retains its evidence method and granularity under D007.
This fixture uses whole scalar values and assumes complete capture of the listed operations.

## Expected trace for the taken branch

This case assumes supported rules for date adjustment and comparison.
The persistence function returns normally. Its internal writes remain opaque.
The table follows logical execution order. It does not require that a transport deliver records in that order.

| Step | Expected logical records | Evidence and meaning |
| --- | --- | --- |
| 1. Observe inputs | Input observations for `A`, `B`, `O`, and `K`, with the origins listed above | Observed fixture boundaries establish four inputs within this scope |
| 2. Enter `process` | Start `E1`. Argument uses: `first → A`, `second → B`, `offset → O`, `cutoff → K` | Generated call propagation preserves upstream handles. Entry alone establishes no derivation |
| 3. Bind `copied` | Binding occurrence within `E1`: `copied → A` | Generated assignment propagation preserves `A`. No new value version appears |
| 4. Adjust the date | `E2`, called by `E1`, receives `receiver → A` and `interval → O`. It produces and returns new handle `S`, containing `1060` | The supported adjustment rule establishes `S` derived from `A` and `O`, through `E2`, with distinct operand roles |
| 5. Bind `shifted` | Binding occurrence within `E1`: `shifted → S` | The returned handle reaches the destination binding |
| 6. Compare | `E3`, called by `E1`, receives `left → S` and `right → K`. It produces and returns new Boolean handle `P`, containing `true` | The supported comparison rule establishes `P` derived from `S` and `K`, through `E3` |
| 7. Select the branch | `D1`, within `E1`, records condition `P`, result `true`, and the taken branch site | Generated branch observation identifies this decision occurrence |
| 8. Call persistence | `E4`, called by `E1`, receives `value → S`. A control relationship links `D1` to this invocation | `S` is the argument. `D1` explains the local branch that allowed the invocation |
| 9. Return from persistence | `E4` returns normally with no tracked result value | This records the call outcome. It does not establish a save or durable commit |
| 10. Return from `process` | `E1` returns the existing handle `B` and completes normally | Generated return propagation preserves `B`. It does not create a result derived from every argument of `E1` |

The tracked value set is exactly `{A, B, O, K, S, P}` under these scope assumptions.
`copied` adds a location for `A`. It does not add a seventh value.
The function return adds a use of `B`. It does not allocate another value handle.
This record proposal uses four operation executions and one branch observation within the fragment.
Source occurrences precede the fragment. Asynchronous deliveries, internal library operations, and internal persistence operations are outside this example's scope.

The supported value derivations are:

```text
S derives from A as receiver and O as interval, through E2.
P derives from S as left operand and K as right operand, through E3.
```

The adjustment already exercises a merge of two input versions with distinct operand roles.

The local control relationship is separate:

```text
D1 observes P == true and gates the invocation E4.
E4 receives S as its argument.
```

`K` helps determine whether `persist` runs. It does not contribute to the contents of `S`.
`B` remains independent of `A` in this fixture despite their equal contents.
The call relationship from `E1` to `E4` alone proves neither value derivation nor a database commit.

## Questions the trace must answer

| Question | Expected answer for this fixture |
| --- | --- |
| Which values produced `S`? | `A` and `O`, through `E2`. Neither `B` nor `K` contributes to its contents |
| Why did persistence run? | `D1` observed a true condition. That condition derives from `S` and `K` through `E3` |
| Where did `B` go? | Into the `second` argument of `E1`, then through its return. It does not flow into `S` or `E4` |
| Where did the copy of `A` go? | Into the `copied` binding, then the receiver argument of `E2` |
| Did the store save `S`? | Unknown. The baseline observes a normal persistence return without an internal save boundary |

A lineage query must traverse relationships according to their meanings.
Unrestricted graph reachability through an execution's inputs and outputs can invent dependencies.
The separate participation, derivation, forwarding, and control records prevent that inference.

## Variants that expose incorrect rules

Each row describes a separate case. Its labels follow the notation above, not reused capture identities.

| Variant | Required trace difference | Incorrect conclusion to reject |
| --- | --- | --- |
| The caller supplies the same tracked date to both date parameters | Both argument roles carry `A`. Returning `second` returns `A` | A new root for every parameter |
| The offset is `0` | Adjustment still creates `S` through `E2`, even though its contents equal `A` | Equality collapses a transformation result into its input |
| The cutoff is `2000` | `P` is false. `D1` records the untaken branch. No `E4` occurs. `E1` returns `B` | An invented persistence execution with a skipped outcome |
| Persistence throws | `E4` records an error outcome. `E1` propagates that error and does not return `B` | A normal return, proven rollback, or proof that no side effect occurred |
| The adjustment has no supported propagation rule | Its argument uses and returned observation remain visible. The relationship from its result to its inputs remains unknown | Exact derivation from every argument solely because the call returned a value |
| Capture starts at function entry with no upstream metadata | Each argument has unavailable ancestry. The trace cannot prove independent roots or shared provenance from contents alone | Equal contents establish common origin, or separate parameters establish independent origin |
| An ancestor record is lost or evicted | Surviving references retain their handles and identify the missing evidence | A missing parent turns a derived value into a proven source input |

The false-branch case assumes its branch observation and execution coverage are available.
An absent persistence record alone cannot establish that the branch was untaken.
Capture loss must remain distinguishable from an observed untaken branch.

## Persistence needs separate evidence

The baseline case deliberately stops at an observed invocation and its outcome.
A reusable persistence adapter can add stronger facts only at boundaries it actually observes.

| Additional observation | Supported claim |
| --- | --- |
| Staging completes | This operation staged a write using the specified value version |
| The store reports save completion | The identified save operation reached that store's completion boundary |
| The outer operation returns or throws | The caller observed that separate operation outcome |

The adapter must associate each fact with its actual operation or transaction.
Temporal proximity and equal values cannot establish that association.
A save completion does not establish an unobserved cloud upload or a stronger storage durability guarantee.
An error after a side effect does not erase an earlier observed completion.
The later GPS example must apply the store-specific boundaries documented in [005](005-explicit-tracing-and-code-generation.md).

## What the generator must preserve

This notation expresses propagation obligations rather than an implementation:

```text
on entry:         first -> A, second -> B, offset -> O, cutoff -> K
on copy:          copied -> A
on adjustment:    result -> S, with supported derivation through E2
on assignment:    shifted -> S
on comparison:    condition -> P, with supported derivation through E3
on persistence:   argument -> S
on normal return: result -> B
```

Generated metadata must follow parameter passing, local bindings, and return values.
It must identify the actual called operation before applying a semantic rule.
A method name alone cannot establish the rule for an overloaded or unrelated function.
The generator must also preserve normal evaluation, thrown errors, and the original domain result.
It cannot evaluate an expression again merely to observe it.

Source adapters can establish new external observations without annotations on each application function.
A graph store alone cannot recover the distinctions in this example after metadata is lost.
The [shadow propagation proposal](007-value-identity-and-provenance.md#carrying-the-handle-in-swift) describes candidate mechanisms for those obligations.
None of those mechanisms is selected or validated by this worked trace.

## Consequences for the next discussion

The example recommends separate records for value versions and their occurrences at source sites.
That separation preserves copy provenance while showing where a value travels.
It also requires honest origin evidence and separate persistence outcomes.
These record details remain a proposal under D007, not an additional accepted decision.

The next worked example can extend this model to a batch with filtering, reordering, repeated elements, and a merge.
That example must distinguish a value handle from an element occurrence and collection membership.
Mutation, retries, and asynchronous delivery remain additional cases in the [observation contract](008-observation-contract.md#next-design-checkpoint).
Implementation feasibility remains a later checkpoint in the [plan](../PLAN.md#next-technical-checkpoint).
