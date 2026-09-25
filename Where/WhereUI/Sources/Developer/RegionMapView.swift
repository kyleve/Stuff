import MapKit
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Developer tool: draws region boundary polygons on a real map, toggling
/// between what `RegionAttributor` actually loads (`.attribution`) and the
/// full authored GeoJSON (`.source`).
///
/// Self-contained on purpose — it reads geometry straight from
/// `RegionGeometryCatalog` and holds no `@Environment(WhereSession.self)`,
/// so the same view backs both the in-app developer overlay entry and
/// the standalone `RegionViewer` Mac Catalyst app (which has no session /
/// dependency injection). The catalog decodes off the main thread, so the
/// `.task` below never blocks the UI on the heavy `.source` parse.
public struct RegionMapView: View {
    @State private var kind: RegionGeometryKind = .attribution
    /// One `Result` rather than parallel value/error/loading flags:
    /// `nil` is "not loaded yet", success and failure can't both be set.
    @State private var outlines: Result<[RegionOutline], Error>?
    /// When set, the map and camera narrow to the one feature with this
    /// title (keeps the dense source geometry manageable to render).
    @State private var selectedTitle: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    /// Public so the standalone `RegionViewer` app (a separate module) can
    /// present the same screen as the in-app developer overlay entry.
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            kindPicker
            stateContent
        }
        .navigationTitle(String(localized: .regionMapTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: kind) { await load() }
    }

    private var kindPicker: some View {
        Picker(String(localized: .regionMapKindPicker), selection: $kind) {
            ForEach(RegionGeometryKind.allCases, id: \.self) { kind in
                Text(WhereFormat.regionMapKind(kind)).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var stateContent: some View {
        switch outlines {
            case .none:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .some(.failure(error)):
                ContentUnavailableView(
                    String(localized: .regionMapLoadErrorTitle),
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(error.localizedDescription),
                )
            case let .some(.success(loaded)) where loaded.isEmpty:
                ContentUnavailableView(
                    String(localized: .regionMapEmptyTitle),
                    systemSymbol: .map,
                    description: Text(String(localized: .regionMapEmptyDescription)),
                )
            case let .some(.success(loaded)):
                VStack(spacing: 0) {
                    map(for: visibleOutlines(in: loaded))
                    legend(for: loaded)
                }
        }
    }

    private func map(for outlines: [RegionOutline]) -> some View {
        RegionOutlinesMap(
            outlines: outlines,
            cameraPosition: $cameraPosition,
            color: color(for:),
        )
        .frame(maxHeight: .infinity)
        .accessibilityLabel(String(localized: .regionMapMapAccessibility))
    }

    private func legend(for loaded: [RegionOutline]) -> some View {
        RegionMapLegend(
            kind: kind,
            groups: legendGroups(for: loaded),
            selectedTitle: selectedTitle,
            color: { color(forTitle: $0.title, region: $0.region) },
            onSelect: select,
        )
        .frame(height: stylesheet.regionMap.height)
    }

    // MARK: - Data

    private func load() async {
        outlines = nil
        selectedTitle = nil
        do {
            // Standalone dev tool with no session/store, so `.attribution` shows
            // every available region the engine can attribute (`.all`); `.source`
            // ignores the attributor.
            let loaded = try await RegionGeometryCatalog.outlines(for: kind, attributor: .all)
            guard !Task.isCancelled else { return }
            outlines = .success(loaded)
            reframe(to: loaded)
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the failure observable in both the UI (the `.failure`
            // state renders an error) and the logs, rather than silently
            // showing an empty map.
            RegionLog.geometryCatalog.loadFailed(
                kind: .restricted(.technicalState, kind.rawValue),
                description: .restricted(.errorDetails, String(describing: error)),
            )
            outlines = .failure(error)
        }
    }

    private func select(_ title: String?) {
        selectedTitle = title
        guard case let .success(loaded) = outlines else { return }
        reframe(to: visibleOutlines(in: loaded))
    }

    private func visibleOutlines(in loaded: [RegionOutline]) -> [RegionOutline] {
        guard let selectedTitle else { return loaded }
        return loaded.filter { $0.title == selectedTitle }
    }

    /// One legend entry per feature title, in first-seen order, carrying
    /// how many sub-polygons it drew (a MultiPolygon yields several).
    private func legendGroups(for loaded: [RegionOutline]) -> [RegionMapLegendGroup] {
        var groups: [RegionMapLegendGroup] = []
        var indexByTitle: [String: Int] = [:]
        for outline in loaded {
            if let index = indexByTitle[outline.title] {
                groups[index].outlineCount += 1
            } else {
                indexByTitle[outline.title] = groups.count
                groups.append(RegionMapLegendGroup(
                    title: outline.title,
                    region: outline.region,
                    outlineCount: 1,
                ))
            }
        }
        return groups
    }

    // MARK: - Camera

    private func reframe(to outlines: [RegionOutline]) {
        cameraPosition = Self.cameraPosition(enclosing: outlines)
    }

    /// A camera framed to `outlines` via ``enclosingRegion(of:)``. Falls back
    /// to `.automatic` when there's nothing to show.
    private static func cameraPosition(enclosing outlines: [RegionOutline]) -> MapCameraPosition {
        guard let region = enclosingRegion(of: outlines) else { return .automatic }
        return .region(region)
    }

    /// The coordinate region framing `outlines` (with a little padding), or
    /// `nil` when there's nothing to show. Latitude comes from `BoundingBox`
    /// (latitude never wraps); longitude from `LongitudeSpan`, which is
    /// antimeridian-aware — so filtering to Alaska frames the Aleutians
    /// tightly instead of zooming out to the whole globe (its rings span
    /// ~+172° across 180° to ~−130°). Shared by the live camera and the
    /// snapshot stand-in, so both frame identically.
    fileprivate static func enclosingRegion(of outlines: [RegionOutline]) -> MKCoordinateRegion? {
        guard let box = BoundingBox.enclosing(outlines),
              let longitude = LongitudeSpan.enclosing(
                  outlines.lazy.flatMap { $0.coordinates.lazy.map(\.longitude) },
              )
        else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (box.minLatitude + box.maxLatitude) / 2,
            longitude: longitude.center,
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((box.maxLatitude - box.minLatitude) * 1.3, 1), 170),
            longitudeDelta: min(max(longitude.degrees * 1.3, 1), 350),
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Color

    private func color(for outline: RegionOutline) -> Color {
        color(forTitle: outline.title, region: outline.region)
    }

    /// A region keeps its `RegionStyle` tint; an untagged source feature
    /// gets a stable color derived from its title so the same feature is
    /// always the same hue across launches.
    private func color(forTitle title: String, region: Region?) -> Color {
        if let region { return regionStyles.style(for: region).tint }
        return Self.palette[Self.paletteIndex(for: title)]
    }

    private static let palette: [Color] = [
        .red,
        .orange,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .pink,
        .brown,
        .gray,
    ]

    private static func paletteIndex(for title: String) -> Int {
        let sum = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sum % palette.count
    }
}

/// The map surface for ``RegionMapView``: the live MapKit `Map`, or — under
/// snapshot capture — a deterministic stand-in of identical layout. Owning the
/// `\.isCapturingSnapshot` branch here keeps the capture check out of
/// `RegionMapView` itself: the screen just renders this, unaware which substrate
/// it drew. MapKit's tile/label loading is asynchronous and cache/network-
/// dependent, so no settle window can make the real substrate pixel-stable; the
/// view's own overlays (the region polygons) still render for real in the
/// stand-in — only the tile substrate is replaced — per the
/// `\.isCapturingSnapshot` carve-out (see SnapshotKit's `SnapshotCaptureFlag`).
private struct RegionOutlinesMap: View {
    let outlines: [RegionOutline]
    @Binding var cameraPosition: MapCameraPosition
    let color: (RegionOutline) -> Color

    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var body: some View {
        if isCapturingSnapshot {
            SnapshotMapStandIn(
                outlines: outlines,
                region: RegionMapView.enclosingRegion(of: outlines),
                color: color,
            )
        } else {
            Map(position: $cameraPosition) {
                ForEach(outlines) { outline in
                    MapPolygon(coordinates: outline.coordinates.clLocationCoordinates)
                        .foregroundStyle(color(outline).opacity(0.25))
                        .stroke(color(outline), lineWidth: 1.5)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
        }
    }
}

/// Deterministic stand-in for ``RegionMapView``'s live `Map` under snapshot
/// capture: the same outlines, drawn with the same fill/stroke styling over a
/// flat substrate, framed by the same enclosing-region math as the live
/// camera — identical layout, none of MapKit's cache/network-dependent
/// tile/label loading.
///
/// Coordinates project equirectangularly (a plain degrees-to-points scale
/// around the region's center, longitude unwrapped across the antimeridian).
/// That's not MapKit's Mercator, so shapes sit slightly differently than on
/// the live map — fine for a capture stand-in whose job is a stable, honest
/// rendering of the view's own overlays.
private struct SnapshotMapStandIn: View {
    let outlines: [RegionOutline]
    /// The frame the live camera would use; `nil` (nothing to show) renders
    /// just the substrate.
    let region: MKCoordinateRegion?
    let color: (RegionOutline) -> Color

    var body: some View {
        Canvas { context, size in
            guard let region, size.width > 0, size.height > 0 else { return }
            // MapKit fits a camera region so both spans are fully visible;
            // the larger degrees-per-point axis sets the scale here too.
            let degreesPerPoint = max(
                region.span.longitudeDelta / size.width,
                region.span.latitudeDelta / size.height,
            )
            guard degreesPerPoint > 0 else { return }

            func point(for coordinate: Coordinate) -> CGPoint {
                // Unwrap the longitude delta to [-180°, 180°) so a region
                // straddling the antimeridian stays contiguous.
                let deltaLongitude = (coordinate.longitude - region.center.longitude + 540)
                    .truncatingRemainder(dividingBy: 360) - 180
                return CGPoint(
                    x: size.width / 2 + deltaLongitude / degreesPerPoint,
                    y: size.height / 2
                        + (region.center.latitude - coordinate.latitude) / degreesPerPoint,
                )
            }

            for outline in outlines {
                guard let first = outline.coordinates.first else { continue }
                var path = Path()
                path.move(to: point(for: first))
                for coordinate in outline.coordinates.dropFirst() {
                    path.addLine(to: point(for: coordinate))
                }
                path.closeSubpath()
                let tint = color(outline)
                context.fill(path, with: .color(tint.opacity(0.25)))
                context.stroke(path, with: .color(tint), lineWidth: 1.5)
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

#if DEBUG
    extension RegionMapView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            // The production screen intentionally bounds this list beneath the
            // map. Capture the shared scrollable content itself so every feature
            // is visible without teaching the production split layout a
            // snapshot-only sizing mode.
            whereSnapshot(name: "Default", configurations: .fullContentPhoneLightDark) {
                RegionMapLegend(
                    kind: .attribution,
                    groups: snapshotLegendGroups,
                    selectedTitle: nil,
                    color: { group in
                        group.region.map { RegionStyle.fallbackStyle(for: $0).tint } ?? .gray
                    },
                    onSelect: { _ in },
                )
            }
        }

        private static var snapshotLegendGroups: [RegionMapLegendGroup] {
            RegionCatalog.shared.all.enumerated().map { index, region in
                RegionMapLegendGroup(
                    title: region.localizedName,
                    region: region,
                    outlineCount: index.isMultiple(of: 10) ? 2 : 1,
                )
            }
        }
    }

    // The live `Map` preview stays alongside the cutsheet: the cutsheet renders
    // the deterministic capture stand-in (`\.isCapturingSnapshot` is set there),
    // but a developer previewing this screen still wants the real MapKit map.
    #Preview("Live map") {
        NavigationStack {
            RegionMapView()
        }
    }

    #Preview("Snapshot cutsheet") {
        RegionMapView.snapshotPreviews
    }
#endif

#if DEBUG
    extension RegionMapView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RegionMapView.self,
            title: "Region Map",
        )
    }
#endif
