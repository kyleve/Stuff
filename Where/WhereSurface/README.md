# WhereSurface

**WhereSurface** is the Foundation-only contract between the Where app and
small store-free glance processes such as the native macOS menu bar helper.

The app remains the sole owner of SwiftData and CloudKit. It publishes a
presentation-ready `WhereSurfaceSnapshot` inside the existing
`widget-snapshot.json` App Group artifact. A helper reads that file through
`WhereSurfaceStore`, renders the supplied order and localized names, and never
links `WhereCore`, `RegionKit`, SwiftData, CloudKit, or location services.

## Public API

- `WhereSurfaceSnapshot` carries today's observed regions and the top
  year-to-date day counts.
- `WhereSurfaceDocument` decodes only `generatedAt` and `surface` from the
  larger widget JSON document. Both are optional for compatibility with older
  app versions.
- `WhereSurfaceStore` resolves `group.com.stuff.where` and provides read-only
  access to `widget-snapshot.json`.
- `WhereSurfaceFileCoordinator` coordinates every artifact read and atomic
  replacement across the app, widget, and helper processes.
- `WhereSurfaceChangeNotification` is an advisory Darwin notification. The
  JSON file is always authoritative.

Consumers keep the last good value if a later read fails. The helper does not
launch the app automatically; `WhereSurfaceStore.openWhereURL` is offered only
for an explicit user action.

## Testing

`WhereSurfaceTests` covers wire compatibility, Foundation-only decoding,
coordinated file access, and reads. The app's WhereCore tests cover
construction, ranking, and publication of the payload from real domain data.
