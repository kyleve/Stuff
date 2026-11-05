# Reviewed recording choices

Run `./tla-check ReviewedRecordingChoices` from the repository root.

This model asks whether a retry retains the reviewed operation and causal context.
It also checks that changed evidence observed during reassessment requires another review.
It represents `RecordingReviewTransaction`, shared by the source-choice and control-edit coordinators.
The shared transaction was extracted from the source-choice implementation at `36372012`.

## Source correspondence

| Model | Source boundary |
| --- | --- |
| `Preview`, `operationID` | Each coordinator's `review` creates one immutable control identity in its proposal. |
| `evidence`, `decisions` | The relevant observation and control values in `RecordingReviewEvidence`. |
| `ReadSnapshot` | `RecordingReviewReader.evidence` reads through `WhereStore.readSnapshot`. |
| `CompareReview` | `RecordingReviewTransaction.apply` compares current evidence with the proposal's evidence. |
| `stagedPredecessors` | The proposal's original predecessor set, encoded by `RecordingControlCodec`. |
| `history`, `CommitGuard` | The store's persistent-history check can reject a crossing commit before save. |
| `generation` | The expected data generation passed to `perform`; Reset rotates it. |
| `permit`, `commitLock` | The compatibility permit and its physical-save mutex. |
| `PhysicalSave`, `stored` | The immutable envelope saved by the outer transaction. |
| `ReceiveOutcome` | A successful save can outlive delivery of its result to the caller. |
| `Begin` after retry | An identical committed envelope completes without allocating another operation. |

Each asynchronous read and validation boundary has a separate action.
The model abstracts the internally consistent snapshot into one read.
The Swift store rejects external changes that cross that snapshot or its later history check.
An unrelated import changes the history token without changing the relevant evidence.
The next attempt can then save the original proposal without another user confirmation.

## Bounds and limitations

One proposal can attempt two or three saves.
One sample import, one decision import, one unrelated import, one reset, and one retirement can race with it.
One successful save can lose its response and retry.
Identity allocation assumes fresh UUIDs for new operations; it does not prove UUID uniqueness.
Swift admission rejects collisions and preserves identities through archive imports.

Remote imports can interleave between `CommitGuard` and `PhysicalSave`.
The model does not claim that a synchronous history check locks out another process or CloudKit.
The checked evidence is what reassessment observed, not every change that another device may hold or deliver later.
Generation changes leave old-generation records inert; this model checks that retries never rebind them to a new generation.
The existing compatibility-write model owns the separate permit lifetime properties.

This is a safety model without scheduling or delivery fairness.
The stuttering process permits completed or blocked work without a deadlock claim.
Calendar payload semantics, geographic assessment, service-scope identity, UI presentation, and post-commit fan-out are outside its bounds.
The Swift regressions cover these implemented boundaries separately; production selection remains inactive.

## Controls and regressions

The broken controls adopt newly received predecessors, ignore changed evidence, allocate another identity on retry, or rebind a staged operation after Reset.
Each must fail its named invariant.
Reachability controls require a successful retry, recovery after a lost response, and rejection of changed evidence.

`RecordingChoiceCoordinatorTests` holds the production save before its write, imports relevant or unrelated controls, and resumes it.
It also covers duplicate retry, concurrent choices after commit, reset, permit revocation, service replacement, and complete whole-day context.
`RecordingReviewReaderTests` covers late causal ancestors outside the displayed period and correction/removal/manual inputs.
`RecordingControlEditCoordinatorTests` covers the shared protocol for ignore, place, and calendar edits.
Its late calendar contradiction test verifies an invalid refreshed edit fails before append; this domain rule is outside the model.
`RecordingReviewTransactionTests` covers exhausted retries and preservation of the original operation on a later attempt.
TLC results belong to the exact model bounds and assumptions above; they do not prove the Swift implementation.

## Checked result

On 2026-11-04, all nine manifest expectations passed with PlusCal 1.11, TLC 1.7.4, and Temurin 21.0.8+9.
The tool archive SHA-256 was `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
After the shared-transaction extraction, the checker retained generated source, traces, and `summary.json` under `.build/tla/runs/ReviewedRecordingChoices.6rr8xE/`.

| Configuration | Result | Generated / distinct states | Depth |
| --- | --- | ---: | ---: |
| `Current.cfg`, two attempts | Pass | 6,767 / 1,829 | 21 |
| `CurrentThreeAttempts.cfg`, three attempts | Pass | 7,520 / 2,071 | 22 |
| `AdoptNewer.cfg` | Expected predecessor failure | 1,498 / 487 | 9 |
| `IgnoreEvidence.cfg` | Expected evidence failure | 1,349 / 447 | 9 |
| `NewRetryID.cfg` | Expected identity failure | 1,742 / 551 | 10 |
| `RebindGeneration.cfg` | Expected generation failure | 1,214 / 416 | 9 |
| `RetryReachability.cfg` | Retry success reached | 6,055 / 1,689 | 16 |
| `LostResponseReachability.cfg` | Lost-response recovery reached | 2,264 / 694 | 11 |
| `ChangedReviewReachability.cfg` | Changed review reached | 95 / 52 | 5 |

The inspected negative traces show these failures:

- A remote choice arrives after preview. The broken writer adopts it without review.
- A sample arrives after preview. The broken comparison accepts its changed evidence.
- A save succeeds but loses its response. The broken retry replaces its operation identity.
- Reset follows the final history check. The broken writer attaches old reviewed work to the new generation.

**Verified for these model bounds and assumptions.** No liveness or global CloudKit serialization claim is made.
