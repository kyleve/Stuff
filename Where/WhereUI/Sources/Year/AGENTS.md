# Calendar and timeline contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- Publish flight notices, historical indicators, correction reviews, and actionable counts from one
  `YearReportModel` scan result. Inject that scene as the Resolve model's `ResolutionSource`. Re-key on raw evidence changes; never gate refresh
  on aggregate-report equality. Schedule presentation deadlines only in the foreground.
- Expose each calendar month as one accessibility element: regional totals in the label, chronological stay spans and dated badges in the value. Preserve planning qualifiers. Guard: `CalendarMonthAccessibilityTests`.
- Keep overview availability derived from the full-size calendar visibility rule in `CalendarModel`. Unavailable months keep their region and projection colors, and remain actionable for rejection feedback. Guard: `CalendarModelTests`.
- Inject the calendar zoom key at each entry point. Persist mode changes through `CalendarModel` and the existing `WherePreferences` keys; a nil key must not read or write preferences. Guard: `CalendarModelTests`.
- Animate calendar zoom in an overlay after the destination scroll position settles. Keep moving geometry outside the scroll-target layout and cancel it when its viewport or report changes. Reduce Motion uses a crossfade. Guards: `CalendarZoomTransitionStateTests`, `CalendarContentViewTests`.
- Keep calendar flight days and timeline flight events independent of review dismissal.
  Show uncertain arrival timing explicitly. Render supported travel periods separately from later ground observations.
  Split timeline stays only for presentation; preserve every region-day exactly once.
  Keep a stay intact when departure falls on its final day. Guard: `PresenceJourneyItemTests`.
  Keep overlapping visits intact across regions. Keep shared days in each region exactly once.
- In the full timeline, anchor the initial viewport to the estimate when available. Place it below the current recorded row and its joined planned segment, before later rows.
- Measure calendar month sections, day rows, and Timeline rows eagerly so full-content measurement and scroll restoration use their actual heights. Guards: `CalendarContentViewSnapshotTests`, `PresenceTimelineListSnapshotTests`.
- Keep Your Year in one navigation stack with its bottom calendar/timeline selector at every size. Guard: `YearViewTests`.
