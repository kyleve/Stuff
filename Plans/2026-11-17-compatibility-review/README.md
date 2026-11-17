# Compatibility lockout review

## Planning checkpoint

- Updated: 2026-11-17, starting at `fd31d5a022d0171fe6f2d9c5971b9ebc3e5b4231`.
- Operation: execute the changes approved in the conversation, including individual feedback on [PR #495](https://github.com/kyleve/Stuff/pull/495).
- Stage: implementation; source and all 11 human review threads inspected.
- Completed: agreed behavior and scope reviewed against the existing launch, compatibility, and recording contracts.
- Pending: [implementation and verification](01-ownership.md); tracked in [STU-333](https://linear.app/kve/issue/STU-333). STU-206/208 describe a different per-entity migration design.
- Next action: make shutdown ownership and coordinator injection explicit, then consolidate startup state.

## Outcome, stories, and requirements

| ID | Story / requirement | Deliverable |
| --- | --- | --- |
| US-01 | A user must never see or record into history that the installed build cannot safely open. | R-01–R-03 |
| US-02 | Maintainers need explicit startup ownership and a response to every review comment. | R-04–R-06 |
| R-01 | Preserve pre-open admission, immediate history masking/GPS retirement, draining, and recovery without overlapping real scopes. | [01](01-ownership.md) |
| R-02 | Only real installation recording consent and permission can publish compatibility metadata; demo has no lockout bypass and cannot publish simulated activity. | [01](01-ownership.md) |
| R-03 | Keep permission available before opening history, avoiding the newer-recorder admission deadlock. | [01](01-ownership.md) |
| R-04 | Inject one coordinator; represent startup resources and tasks in valid states; separate durable onboarding completion from current startup state. | [01](01-ownership.md) |
| R-05 | Give terminal task retirement a common shutdown contract and explicitly own live attribution cleanup. | [01](01-ownership.md) |
| R-06 | Simplify lockout layout using the shared screen root; clarify CloudKit container/push behavior; reply to all addressed threads. | [01](01-ownership.md) |

## Exclusions

- X-01: No per-API compatibility checks, data migration, per-entity versioning, or changes to CloudKit publication semantics.
- X-02: No new notification permission onboarding, repository-wide formatter policy, or LifecycleKit rewrite.
- X-03: No promise of demo access during lockout. Synthetic demo permission must never authorize real publication.

## Evidence and decisions

The existing coordinator already separates CloudKit control metadata from SwiftData, accounts for stale decisions, and persists account-bound receipts. Existing Swift tests and `CompatibilityLockout` / `CompatibilityPublication` PlusCal specifications guard those decisions. The review concerns ownership and unnecessary representable states around that protocol.

The user approved the reviewed recommendations on 2026-11-17: retain the pre-store permission step with an installation owner; remove demo's lockout exception; require injection; distinguish terminal shutdown from reversible location stop; and simplify layout. These supersede the former demo-bypass guidance. `LifecycleRunner` still serializes cancel-and-drain transitions.

## Questions and resolutions

| ID | Status | Resolution and integration |
| --- | --- | --- |
| Q-01 | closed | Demo can be gated, but cannot publish simulated recording. User approval; integrated into R-02/X-03 and verification. |
| Q-02 | closed | Permission remains available before admission. Build N+1 cannot publish N+1 without recorder eligibility, so after-open-only permission deadlocks. Integrated into R-03. |

## Execution order and horizon

One [executable plan](01-ownership.md) covers the accepted review. Commit independently verified groups: shutdown ownership, startup/injection/eligibility, and UI/clarifications. Update source-to-model correspondence and repeat affected formal cases with the lifecycle work.

## Plan review

- Reviewed 2026-11-17 against `fd31d5a02`, the complete human feedback, and launch/recording contracts.
- Preserve the repeated-lockout regression: retirement tasks can outlive scope release while replacement launch work drains. Cancellation must prevent obsolete tasks from retiring replacement scopes.
- Keep durable onboarding preference separate from admission; recorder choice UI can be available before history opens.
- No material product questions remain. Ready for authorized execution. Diagrams and sketches describe ownership, not compilation evidence.
- Physical CloudKit propagation and live system prompts remain device-validation limits.

## Delivery

Implementation and review replies stay on [PR #495](https://github.com/kyleve/Stuff/pull/495). Do not merge or resolve review threads without a request.
