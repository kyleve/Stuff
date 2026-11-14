# Settings contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- Keep InstallerKit’s `UpdateModel` process-owned and inject it at `RootView`.
  Poll only from a foreground, non-demo app surface. Keep the last successful
  result visible on failure. Keep App Updates first in Settings for eligible builds,
  including local and current builds. Show the update badge only when an update needs attention.
  Guard: `SettingsSearchTests.updatesRequireAnEligibleBuildAndStayOutOfDemo`.
  Install actions use InstallerKit's validated
  system-installer URL for the displayed build.
  Render the detail with InstallerKitUI's shared `AppUpdatesView`. Supply Where branding
  and Settings search modifiers through its section-decoration seam.
  Keep refresh and supersession policy in InstallerKit.
  Guard: `InstallerKitTests/UpdateModelTests`.

- The app injects its configured primary icon name at `RootView`; icon-picker
  code treats every manifest entry as an asset and derives primary versus
  alternate status from that injected name.
- Keep backup import onboarding-only. Settings exports archives but never
  starts or resumes an import (`BackupModelTests`).
  Attach export sheets and error alerts to `DataSettingsView` outside its `Form` sections.
- Keep diagnostic reporting's saved, process-effective, applying, and failed
  states distinct. Crash and replay choices stay pending until relaunch.
  Remote-log revisions apply live. A runtime failure invalidates in-flight
  applies. An older completion must never win.
- Keep the combined personal-data switch scoped to its named controls. Preserve consumer-defined grants and use effective policy for privacy disclosures.

## Feature discovery

Keep gallery rows and Forms behind small named views inside focus and reveal scopes. Guard: `FeatureGuidePageTests` and the gallery view-size tests.
Keep Explore Features browsing read-only. Use production presentation components and explicit actions into existing editors.
Use `PresenceTimelineList` with `.excerpt` for embedded Timeline galleries; keep row layout and planned-stay joins in that view.
Use process-effective diagnostics for privacy claims. Hide gallery links whose destinations are unavailable in demo mode.
Use the [`update-explore-features`](../../../../.agents/skills/update-explore-features/SKILL.md) skill for periodic coverage updates.
