# Where — Feature contracts

Read the [repository contract](../AGENTS.md) first. Module READMEs own APIs; module instructions own local contracts.

Where combines passive GPS and user assertions into per-day region presence.
A day can count for multiple regions. Effective sample attribution and additive manual entries contribute unless an authoritative overlay replaces them.
Device removal and GPS corrections change effective attribution; preserve raw observations for review and backup.

## Layering

- WhereCore depends on RegionKit; WhereUI depends on WhereCore; app, intent, widget, and share-extension hosts consume those layers.
- WhereCore owns domain rules, persistence, and side effects. WhereUI models own observable mirrors, lifecycle wiring, and UI intents. Views own presentation; app targets compose services.
- UI reaches domain behavior through `WhereServices`, never the store or location source directly.
- Mutate the store only inside `WhereStore.perform`. Pass values across that boundary, never SwiftData records.
- Committed writes notify `WhereStore.changes()`. Readers refresh from that signal; write intents do not refresh inline.
- The DEBUG Inspector runtime is selected before launch, is not a `WhereScope`, and must not construct regular app services.

## Required task guidance

Read matching guidance before changing or reviewing the behavior, including tests and callers outside the owning directory.

| Task | Required guidance |
| --- | --- |
| Logging, performance, or launch budgets | [Logging and spans](Guidance/logging.md) |
| GPS acquisition, live-region confidence, or ingestion | [Location contracts](WhereCore/Sources/Location/AGENTS.md) |
| Recording consent, device identities, or recording onboarding | [Recording-device contracts](WhereCore/Sources/Devices/AGENTS.md) |
| Manual entries or their audit records | [Manual-entry contracts](WhereCore/AGENTS.md#manual-entries) |
| Scopes, startup, onboarding, reset, demo, or Flyover ownership | [Launch and demo](Guidance/launch.md) |
| UI, navigation, localization, or previews | [Presentation](Guidance/presentation.md) |
| Dates, calendars, ranges, or day persistence | [Dates](Guidance/dates.md) |
| Physical-device installation, archives, or signing | [Installation](Guidance/installation.md) |
| Any Where test or fixture change | [Testing](Guidance/testing.md) |

New regions are data, not enum cases: see [RegionKit](RegionKit/README.md#adding-a-region).
