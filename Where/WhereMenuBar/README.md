# WhereMenuBar

**WhereMenuBar** is Where's native macOS menu bar companion. It is an
`LSUIElement` helper embedded in the Mac Catalyst app and optionally registered
by the user as a login item.

The status item is icon-only. Its popover shows the regions observed today,
the top three year-to-date day counts, the age of the last successful publish,
and an explicit **Open Where** button. It keeps stale content visible when a
later refresh fails and never launches the main app on its own.

## Data boundary

The helper depends only on [`WhereSurface`](../WhereSurface). It reads the
presentation-ready overlay in the App Group's `widget-snapshot.json` and
treats the Darwin change notification as an advisory refresh hint. It never
opens SwiftData, contacts CloudKit, requests location, or recomputes reports.

## Packaging

The Tuist target is a native macOS app with bundle identifier
`com.stuff.where.menubar`, sandbox + App Group entitlements, and
`LSUIElement = true`. The Catalyst app embeds it in
`Contents/Library/LoginItems` and owns the `SMAppService.loginItem` user
control.
