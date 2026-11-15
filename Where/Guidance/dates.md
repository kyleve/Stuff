# Date contracts

## Dates

- **A logical day is a `CalendarDay` (Y-M-D), not a `Date`.** See
  [`WhereCore/AGENTS.md`](../WhereCore/AGENTS.md). Never persist a day as an
  absolute instant.
- **Year bounds are half-open. Day ranges are inclusive**
  (`Date.calendarDays(through:in:)`, `CalendarDay.days(through:)`).
- **The app is Gregorian-only. Never use `Calendar.current`.** A non-Gregorian
  device calendar silently mismatches the stored reports. Use the calendar the
  owning type vends, or a fresh `Calendar(identifier: .gregorian)` with the
  current time zone (see `Calendar.whereIntents`).
- **Inject `Calendar`. Do not reach for globals.** Prefer calendar APIs over
  hardcoded day/weekday counts (`Calendar.dayCount(ofYear:)`).
- **Core layout APIs throw on failure.** Views surface
  `ContentUnavailableView` + log. Never use `!`.
- Shared date-range copy lives in `DateRangeFormatting`. WhereUI composition
  and value formatting go through `WhereFormat`.
