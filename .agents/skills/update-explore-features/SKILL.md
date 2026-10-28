---
name: update-explore-features
description: Review and update Where’s Explore Features galleries against current app behavior. Use for periodic discovery-content maintenance, missing walkthroughs, or stale feature explanations.
---

# Update Explore Features

Keep Settings > Explore Features useful for people who do not know every Where workflow.
The default invocation updates local files. Leave changes uncommitted and do not push, publish a PR, or create a schedule.
An explicit request for those actions overrides this default.

## Find coverage gaps

1. Read the root and WhereUI `AGENTS.md` files.
2. Read `Where/WhereUI/Sources/Settings/SettingsSearch.swift` and the galleries under `FeaturePreviews` beside it.
3. Compare the galleries with current release-facing screens, settings, widgets, App Intents, and the share extension.
4. Use recent Git history to find changed behavior. Verify each claim against current source and tests.

Start with Locations, Your Year, recording, manual entries, corrections, evidence, planning, customization, and privacy controls.
Follow source registrations to discover additional workflows. Do not treat this list or README prose as a complete feature catalog.
Exclude developer tools and unimplemented backlog features.

Report each gap as a missing workflow, inaccurate claim, outdated visual, missing search entry, or broken action.
Name the source that establishes the behavior. Do not maintain a second persistent coverage inventory.

## Update the galleries

Use the `building-ui` skill and its companion SwiftUI guidance.
Extend an existing page when the topic belongs to its workflow.
Add a page only when the workflow needs its own explanation and visuals.
Keep core workflows before optional integrations in the Explore list.

Reuse production visual components and the existing gallery chrome.
Keep browsing read-only. Do not start location requests, issue scans, exports, recording, or edits to render examples.
Use injected state. Keep example data visibly distinct from actual records.
Preserve honest empty, unavailable, and failed states. A zero issue count alone does not prove a completed scan.
Hide action links whose destinations are unavailable in demo mode.

Read the current privacy presentation and backup contracts before writing claims about them.
Privacy disclosures use process-effective settings. Backup import remains an onboarding flow.
Keep topic titles, search focus items, navigation, Flyover registrations, previews, and snapshots together with each change.
Use localized copy and typed symbols. Update module documentation when its described behavior changes.

If a product decision blocks one change, complete independent updates first.
File deferred work in the lowest applicable `TODOs.md`, using the root backlog format.
Do not invent a product feature to fill a documentation gap.

## Validate and report

Use `running-tests` for affected unit and snapshot checks.
Review full-content images for phone, tablet, dark mode, large text, and contrast.
Verify search focus, navigation, demo behavior, and explicit edit boundaries.
Run the applicable catalog, symbol, and formatting checks.
Report changed pages, source-backed findings, test results, and unresolved decisions.
If coverage is current, report that result and leave files unchanged.
