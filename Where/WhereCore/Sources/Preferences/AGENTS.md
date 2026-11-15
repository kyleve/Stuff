# Preference contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- **Location-card history is non-authoritative preference state.** Keep its
  snapshots year-keyed by stable `Region` id. Clear them through
  `WherePreferences.reset()`. Current report totals remain the source of truth.
- Keep calendar zoom choices device-local and outside backup archives. Use stable `CalendarZoomKey` namespaces and clear all of them through `WherePreferences.reset()`. Guards: `CalendarZoomKeyTests`, `WherePreferencesTests`.
- Keep welcome history in one encoded preference. Distinguish missing history from an explicit reset with no saved region.
  Keep it outside backup archives. Guard: `WherePreferencesTests`.
- **Keep diagnostic reporting intent in one encoded composite preference.** Keep crash,
  replay, remote threshold, and export policy vendor-neutral. Invalid stored
  values assert in Debug and resolve remote logging Off. Reset removes every reporting key.
- **`WhereTheme` is device-local preference state, not backup/domain data.**
  Preserve its stable raw values. Make unknown or missing values Standard. Publish it through
  `WidgetPresentationPublisher`. Never put it in `WidgetSnapshot`. Never rebuild widget data for a
  presentation-only change.
