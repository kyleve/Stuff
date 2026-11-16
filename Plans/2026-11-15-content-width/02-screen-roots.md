# 02 — Screen roots and broader adoption

- Status: executing
- Depends on: [01 — Content width](01-content-width.md)
- Shared context: [Overview](README.md)
- Issue: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies)

## Scope and authorization

The user approved the review recommendations after PR #506 feedback.
This follow-up removes redundant image matrices, adds screen conveniences, and extends the width policy to Settings, Explore Features, and onboarding.
The first plan remains the historical record of the initial rollout.

## Contracts and guards

| Requirement | Owner and existing guard |
| --- | --- |
| Width and padding use stylesheet values. Omitted width inherits the ancestor policy. | Shared presentation contracts; `WhereContentRootTests`, `WhereStylesheetTests` |
| Navigation, sheets, and scroll state retain their owners and identity. | Primary contracts; hosted screen-root and native-container tests |
| Calendar anchors remain outside the constrained column. Timeline keeps its pinned ribbon. | Year contracts; `CalendarContentViewTests` and existing screen snapshots |
| Native forms and lists retain their scrolling, sections, and background. | Building UI layout guidance; hosted native-container tests and existing Settings snapshots |
| Nested screen roots add no second scroller or padding in release. New presentations can establish independent roots. | Shared root guard; focused hosted nesting and presentation coverage |
| Image coverage follows distinct layouts without a theme/device/policy product. | SnapshotKit contracts; retained-reference accounting and `WhereFlyoverCatalogTests` |

## Design

```swift
// Proposed conveniences over the existing width policy.
content.whereScreenRoot() // Inherited width, standard padding, vertical scrolling.
content.whereScreenRoot(.wide, padding: .none)
Form { rows }.whereFormRoot() // Native container retains ownership.
```

The screen modifier composes scrolling, padding, and the existing content root.
A native-container adapter applies content margins from the same width policy.
An optional `WhereScreen` protocol delegates its default body to the screen modifier.
Explicit presentation boundaries reset root nesting without discarding the inherited width.
These modifiers own presentation only. No services or persistence change, so a separate data-flow diagram is unnecessary.

Calendar and Timeline retain their specialized containers. Maps and media previews retain their available width.
The rollout covers Settings details, Explore Features, onboarding, region customization, and license text.
Further data editors and app-icon grid changes remain outside this follow-up.

## Steps and verification

1. Remove the four added snapshot loops, their 18 references, and their configuration helper. Verify retained captures and Flyover identities, then commit and reply.
2. Add screen-root, padding, optional protocol, and native-container support. Verify inheritance, explicit overrides, resizing, identity, nesting fallback, and presentation boundaries.
3. Adopt the helpers on the selected screens. Review changed existing images, record intentional updates, and run separate assertions with recording disabled.
4. Review the final diff independently. Update documentation, PR evidence, issue state, and each addressed review thread. Commit and push each verified step.

Verification uses `./test --no-generate` with focused hosted suites and affected image suites.
The final pass includes the complete WhereUI unit bundle, formatting, and typed-symbol lint.
No additional full-screen snapshot matrices are required.

## Review

- Reviewed against `d8d3c3eb5f0317c407eeff69140caad816399450` and all five human review comments on PR #506.
- The user approved implementation in this conversation.
- The native margin adapter and presentation reset require hosted validation before rollout.

## Progress

- [x] Remove redundant snapshot coverage.
- [ ] Implement and verify shared helpers.
- [ ] Adopt and verify the selected screens.
- [ ] Review, push, and reconcile PR feedback.

## Execution record

- Started from a clean `codex/content-width` checkout. PR #506 still targets `ff3f9ec8` and has no newer source revision.
- Removed exactly 18 new references, the four added loops, and their configuration helper. The retained files are unchanged.
- `./test --no-generate --only WhereUITests/WhereFlyoverCatalogTests --only WhereUISnapshotTests/CalendarContentViewSnapshotTests --only WhereUISnapshotTests/ElsewhereViewSnapshotTests --only WhereUISnapshotTests/LocationsViewSnapshotTests --only WhereUISnapshotTests/PresenceTimelineListSnapshotTests --record never --timings` passed two catalog tests and six image tests covering 183 captures. Formatting passed.

## Resume point

Verify the new screen and native-container helpers before adopting them on additional surfaces.
