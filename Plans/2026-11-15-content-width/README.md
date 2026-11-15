# Content width

## Planning checkpoint

- Updated: 2026-11-15, integrated base `ff3f9ec8df1d7901312624cba805be868f1f7345`.
- Operation: Execute the approved plan on `codex/content-width`.
- Requested scope: The user approved the main-screen rollout and requested implementation after selecting both modifiers.
- Stage: Complete.
- Completed: Implementation, independent review, image review, final assertions, branch push, PR publication, and issue reconciliation.
- Pending: No implementation work remains in this plan.
- Next action: Review [PR #506](https://github.com/kyleve/Stuff/pull/506). The linked Linear issue remains In Review until merge and acceptance verification.

## Outcome and scope

Calendar, Elsewhere, Locations cards, and Timeline use centered content columns inside their existing scroll views.
Each adaptive pane applies its own width limit. Native navigation, backgrounds, and scrolling retain the available width.

## User stories and requirements

| ID | Story |
| --- | --- |
| US-01 | As a user on a wide device, I want readable content without stretched cards and calendars. |
| US-02 | As a UI author, I want inherited width choices without another content closure. |

| ID | Requirement | Story | Plan |
| --- | --- | --- | --- |
| R-01 | `.whereContentRoot()` centers and limits existing padded scroll content. | US-01 | [01](01-content-width.md) |
| R-02 | `.whereContentWidth(_:)` selects regular (600 points), wide (900 points), or fluid (available width). Regular is the default. | US-02 | [01](01-content-width.md) |
| R-03 | The nearest ancestor width override wins. Width changes retain view identity and scrolling state. | US-02 | [01](01-content-width.md) |
| R-04 | The selected screens adopt regular width. Calendar zoom and Timeline header alignment remain correct. | US-01 | [01](01-content-width.md) |
| R-05 | Nested roots assert in debug builds and pass through in release builds. Sibling roots remain independent. | US-02 | [01](01-content-width.md) |

## Exclusions

- X-01: Settings, onboarding, sheets, maps, and Timeline excerpts are outside this rollout.
- X-02: The modifiers add no scrolling, padding, clipping, height limit, or navigation container.
- X-03: No dependency, persistence, or exported API changes are required.

## Discovery and evidence

`CalendarContentView` measures tile anchors relative to a full-width content anchor.
The content anchor must remain outside `.whereContentRoot()` to retain horizontal offsets during zoom.
`PresenceTimelineList` places its year ribbon outside the scroll view at normal text sizes.
The ribbon needs the same content modifier as the rows.
Locations already owns stable navigation above its adaptive panes.
The change does not move that ownership.

Repository evidence is sufficient for this layout change. No external API or platform behavior changes are proposed.

## Questions and decisions

All answers came from the user in this conversation on 2026-11-15.

| ID | Status | Decision | Integration |
| --- | --- | --- | --- |
| Q-01 | closed | Roll out to the four main content screens. | R-04 and X-01. |
| Q-02 | closed | Place the container inside existing scroll views. | R-01 and X-02. |
| Q-03 | closed | Wide means 900 points. Fluid has no fixed cap. | R-02. |
| Q-04 | closed | Width selection is inherited by descendant roots. | R-03. |
| Q-05 | closed | Use `.whereContentRoot()` instead of a wrapper closure. | R-01. |
| Q-06 | closed | Detect nested roots with a debug assertion and use an unconstrained pass-through for inner roots in release builds. | R-05. User requested an assertion and/or a silent fallback during implementation. |
| Q-07 | closed | Accept one-pixel rendering differences from SwiftUI rounding. | The user accepted these differences during snapshot review. The simple two-frame modifier remains in use. |

The existing horizontal padding counts toward each limit. Limits remain fixed across themes and text sizes.

## Execution order and horizon

The current horizon contains one deliverable: [01 — Content width](01-content-width.md).
Its API groundwork and screen adoption form two verified commits on the same branch.

## Plan review

- Reviewed: 2026-11-15 against `2193072f6a1c988f797c77c14c3b6cf0923d8ca0`.
- Scope: All requirements, exclusions, affected layout boundaries, and verification commands.
- Findings: Calendar measurements must include the full-width outer frame. The implementation and tests explicitly retain that boundary.
- Readiness: Ready for authorized implementation. No unresolved product decisions.
- Limits: The proposed Swift shape is not compilation or rendering evidence.

## Review and delivery

- Linear: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies). Searched 328 issues, including archives, before filing this human request.
- Implementation PR: [#506](https://github.com/kyleve/Stuff/pull/506), ready for review.
- Outcome: Completed and published at source revision `3b467e91d4cdf4583d62b4f3614c9716a0a8a1ad`. All 717 WhereUI tests and 325 snapshot captures passed.
