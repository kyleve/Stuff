# Content width

## Planning checkpoint

- Updated: 2026-11-16, integrated base `6676b36bcd7a6dac1d0f7c72784b1d44b7c7f742`.
- Operation: Restore accessibility annotation coverage on `codex/content-width`.
- Requested scope: The user requested retaining the accessibility snapshots removed by the additional reduction.
- Stage: Complete; [04 — Accessibility coverage](04-accessibility-coverage.md) is published.
- Completed: Plans 01–04. Accessibility restoration passed all 58 captures and both catalog tests; PR and issue evidence are updated. Previous CI passed at `af8199887`.
- Pending: CI, PR review, and eventual merge; no implementation work remains in this series.
- Next action: Address subsequent review feedback. STU-331 remains In Review.

## Outcome and scope

Calendar, Elsewhere, Locations cards, and Timeline use centered content columns inside their existing scroll views.
Each adaptive pane applies its own width limit. Native navigation, backgrounds, and scrolling retain the available width.
The approved follow-up adds screen conveniences and native-container support for selected Settings pages, Explore Features, onboarding, region editors, and license text.

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
| R-06 | Screen conveniences compose scrolling and configurable padding. Native Form/List adapters retain their container and scroll identity. | US-02 | [02](02-screen-roots.md) |
| R-07 | Selected additional screens adopt the shared limit, with existing image coverage and focused hosted regression tests. | US-01 | [02](02-screen-roots.md) |

## Exclusions

- X-01: Plan 01 excluded Settings, onboarding, sheets, maps, and Timeline excerpts. Plan 02 adds its selected Settings and onboarding surfaces. Maps and Timeline excerpts retain their existing ownership.
- X-02: The content-root modifier adds no scrolling, padding, clipping, height limit, or navigation container. Plan 02 adds a separate screen convenience that owns scrolling and padding.
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

Answers came from the user in this conversation on 2026-11-15, except Q-11 on 2026-11-16.

| ID | Status | Decision | Integration |
| --- | --- | --- | --- |
| Q-01 | closed | Roll out to the four main content screens. | R-04 and X-01. |
| Q-02 | closed | Place the container inside existing scroll views. | R-01 and X-02. |
| Q-03 | closed | Wide means 900 points. Fluid has no fixed cap. | R-02. |
| Q-04 | closed | Width selection is inherited by descendant roots. | R-03. |
| Q-05 | closed | Use `.whereContentRoot()` instead of a wrapper closure. | R-01. |
| Q-06 | closed | Detect nested roots with a debug assertion and use an unconstrained pass-through for inner roots in release builds. | R-05. User requested an assertion and/or a silent fallback during implementation. |
| Q-07 | closed | Accept one-pixel rendering differences from SwiftUI rounding. | The user accepted these differences during snapshot review. The simple two-frame modifier remains in use. |
| Q-08 | closed | Add screen conveniences, configurable padding, and native-container support, then adopt the selected additional screens. | Plan 02 follows the approved PR review recommendations. |
| Q-09 | closed | Remove the four added full snapshot matrices. | Plan 02 retains existing captures and focused hosted geometry coverage. |
| Q-10 | closed | Merge main and reduce redundant snapshot axes while retaining distinct layout risks. | Plan 03 follows the user's latest request and main's revised coverage policy. |
| Q-11 | closed | Retain the accessibility annotation snapshots removed by the additional reduction. | Plan 04 restores all five iPad annotation captures and their original identities. |

The existing horizontal padding counts toward each limit. Limits remain fixed across themes and text sizes.

## Execution order and horizon

The initial deliverable, [01 — Content width](01-content-width.md), is complete.
The follow-up, [02 — Screen roots](02-screen-roots.md), is also complete.
The follow-up, [03 — Main integration](03-main-integration.md), is complete.
The final correction, [04 — Accessibility coverage](04-accessibility-coverage.md), is complete.

## Initial plan review

- Reviewed: 2026-11-15 against `2193072f6a1c988f797c77c14c3b6cf0923d8ca0`.
- Scope: All requirements, exclusions, affected layout boundaries, and verification commands.
- Findings: Calendar measurements must include the full-width outer frame. The implementation and tests explicitly retain that boundary.
- Readiness: Ready for authorized implementation. No unresolved product decisions.
- Limits: The proposed Swift shape is not compilation or rendering evidence.

## Review and delivery

- Linear: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies). Searched 328 issues, including archives, before filing this human request.
- Implementation PR: [#506](https://github.com/kyleve/Stuff/pull/506), ready for review.
- Initial delivery: Published at source revision `3b467e91d4cdf4583d62b4f3614c9716a0a8a1ad`. All 717 WhereUI tests and 325 snapshot captures passed.
- Review follow-up: Published at source revision `8ffba7b465bde1a445c020ba11b46c06c927b016`. All 723 WhereUI tests and 366 selected captures passed. After the final onboarding correction, all 13 onboarding captures passed again. See plan 02 for commands, independent review, and validation limits.
- Main integration: Merge `cdbdf62cf` preserves all 65 upstream image deletions. All 684 WhereUI tests and 220 distinct retained image references passed across the integration selections. Coverage commit `9d5ab08b9` removes another 18 redundant variants (71→53 captures across five suites). PR #506 and STU-331 contain the final evidence; plan 03 records commands and limits.

- Accessibility correction: `bf561d1a3` restores all five iPad annotation captures removed by the additional reduction. The five suites retain 58 captures, and all 58 plus both catalog tests passed with recording disabled. Restored and retained reference bytes are unchanged.
