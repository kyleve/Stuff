# Day identity and bucketing

Read the [module contract](../../AGENTS.md), [feature date rules](../../../../Where/Guidance/dates.md), and [repository contract](../../../../AGENTS.md) first.

- Persist textual day keys through `CalendarDay.iso8601`, never its diagnostic `description`.
- **A logical day is a `CalendarDay`, not a `Date`.** `CalendarDay` (Y-M-D)
  is the timezone-independent identity every stored user record and day
  comparison keys on. Persisting a `Date` makes a day drift across time-zone
  changes. That is the residency bug this exists to prevent. Use a `Date` only
  for genuine instants (GPS bucketing via `CalendarDay(from:in:)`, grid
  geometry, sorting, display). Derive via `CalendarDay.startOfDay(in:)`.
  **Scope boundary:** only user-asserted records are travel-proof. A GPS
  sample is bucketed into a `CalendarDay` by the *current* calendar at read
  time. A GPS-derived day (and a dismissed GPS-only issue keyed on it) can
  still shift by one across a time-zone change. Deliberate: "where was I on
  this *local* day?" Do not bucket GPS by a fixed home zone.
