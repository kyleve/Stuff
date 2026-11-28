import MapKit
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Developer tool: draws region boundary polygons on a real map, toggling
/// between display coastlines and the boundaries used for GPS tracking.
///
/// Self-contained on purpose — it reads geometry straight from
/// `RegionGeometryCatalog` and holds no `@Environment(WhereSession.self)`,
/// so the same view backs both the in-app developer overlay entry and
/// the standalone `RegionViewer` Mac Catalyst app (which has no session /
/// dependency injection). The catalog decodes off the main thread, so the
/// `.task` below never blocks the UI on the full-catalog decode.
public struct RegionMapView: View {
    @State private var kind: RegionGeometryPurpose = .display
    /// One `Result` rather than parallel value/error/loading flags:
    /// `nil` is "not loaded yet", success and failure can't both be set.
    @State private var outlines: Result<MapData, Error>?
    /// When set, the map and camera narrow to the one feature with this
    /// title (keeps the dense source geometry manageable to render).
    @State private var selectedTitle: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    @Environment(\.regionStyles) private var regionStyles

    /// Public so the standalone `RegionViewer` app (a separate module) can
    /// present the same screen as the in-app developer overlay entry.
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            RegionMapKindPicker(kind: $kind)
            switch outlines {
                case .none:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .some(.failure(error)):
                    RegionMapLoadError(error: error)
                case let .some(.success(loaded)) where loaded.groups.isEmpty:
                    RegionMapEmptyState()
                case let .some(.success(loaded)):
                    RegionMapOverview(
                        data: loaded,
                        isLoading: loaded.kind != kind,
                        selectedTitle: selectedTitle,
                        cameraPosition: $cameraPosition,
                        color: color(for:),
                        legendColor: { color(forTitle: $0.title, region: $0.region) },
                        select: select,
                    )
            }
        }
        .navigationTitle(String(localized: .regionMapTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: kind) { await load() }
    }

    // MARK: - Data

    private func load() async {
        // Keep the live Map mounted while switching products. MapKit owns the
        // gesture-positioned camera, which a new Map cannot restore from its binding.
        if case .failure? = outlines {
            outlines = nil
        }
        let needsInitialFrame = outlines == nil
        do {
            let loaded = try await MapData(kind: kind)
            guard !Task.isCancelled else { return }
            outlines = .success(loaded)
            if needsInitialFrame, cameraPosition == .automatic, let overview = loaded.overview {
                cameraPosition = .region(overview)
            }
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the failure observable in both the UI (the `.failure`
            // state renders an error) and the logs, rather than silently
            // showing an empty map.
            RegionLog.geometryCatalog.loadFailed(
                kind: .restricted(.technicalState, kind.rawValue),
                error: .restricted(.errorDetails, error),
            )
            outlines = .failure(error)
        }
    }

    private func select(_ title: String?) {
        selectedTitle = title
        guard case let .success(loaded) = outlines else { return }
        cameraPosition = loaded.frame(for: title).map(MapCameraPosition.region) ?? .automatic
    }

    struct MapData {
        let kind: RegionGeometryPurpose
        let geometry: RegionMapGeometry
        let groups: [RegionMapLegendGroup]
        let overview: MKCoordinateRegion?
        let frames: [String: MKCoordinateRegion]

        @concurrent init(kind: RegionGeometryPurpose) async throws {
            self.kind = kind
            try Task.checkCancellation()
            let outlines: [RegionOutline] = switch kind {
                case .display:
                    try await RegionGeometryCatalog.displayGeometry(for: RegionCatalog.shared.all)
                        .outlines
                case .tracking:
                    RegionGeometryCatalog.trackingOutlines(for: .all)
            }
            try Task.checkCancellation()
            geometry = RegionMapGeometry(outlines: outlines)
            try Task.checkCancellation()
            overview = RegionMapView.enclosingRegion(of: outlines)
            let byTitle = Dictionary(grouping: outlines, by: \.title)
            frames = byTitle.compactMapValues(RegionMapView.enclosingRegion(of:))
            var titles: Set<String> = []
            groups = outlines.compactMap { outline in
                guard titles.insert(outline.title).inserted else { return nil }
                return RegionMapLegendGroup(
                    title: outline.title,
                    region: outline.region,
                    outlineCount: byTitle[outline.title]?.count ?? 0,
                )
            }
        }

        func frame(for title: String?) -> MKCoordinateRegion? {
            if let title {
                return frames[title]
            }
            return overview
        }
    }

    /// The coordinate region framing `outlines` (with a little padding), or
    /// `nil` when there's nothing to show. Latitude comes from `BoundingBox`
    /// (latitude never wraps); longitude from `LongitudeSpan`, which is
    /// antimeridian-aware — so filtering to Alaska frames the Aleutians
    /// tightly instead of zooming out to the whole globe (its rings span
    /// ~+172° across 180° to ~−130°). Shared by the live camera and the
    /// snapshot stand-in, so both frame identically.
    private nonisolated static func enclosingRegion(of outlines: [RegionOutline])
        -> MKCoordinateRegion?
    {
        guard let box = BoundingBox.enclosing(outlines),
              let longitude = LongitudeSpan.enclosing(outlines, boundedBy: box) else { return nil }
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
        if let region {
            return regionStyles.style(for: region).tint
        }
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
struct RegionOutlinesMap: View {
    let geometry: RegionMapGeometry
    let selectedTitle: String?
    let frame: MKCoordinateRegion?
    @Binding var cameraPosition: MapCameraPosition
    let color: (RegionOutline) -> Color

    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var body: some View {
        if isCapturingSnapshot {
            RegionMapCanvas(
                geometry: geometry,
                selectedTitle: selectedTitle,
                region: frame,
                style: overlayStyle(for:),
            )
        } else {
            RegionPolygonMap(
                geometry: geometry,
                selectedTitle: selectedTitle,
                position: $cameraPosition,
                style: overlayStyle(for:),
            )
        }
    }

    private func overlayStyle(for outline: RegionOutline) -> RegionMapOverlayStyle {
        let tint = color(outline)
        return RegionMapOverlayStyle(fill: tint.opacity(0.25), stroke: tint, lineWidth: 1.5)
    }
}

private struct RegionMapKindPicker: View {
    @Binding var kind: RegionGeometryPurpose

    var body: some View {
        Picker(String(localized: .regionMapKindPicker), selection: $kind) {
            ForEach(RegionGeometryPurpose.allCases, id: \.self) { kind in
                Text(WhereFormat.regionMapKind(kind)).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }
}

private struct RegionMapLoadError: View {
    let error: any Error

    var body: some View {
        ContentUnavailableView(
            String(localized: .regionMapLoadErrorTitle),
            systemSymbol: .exclamationmarkTriangle,
            description: Text(error.localizedDescription),
        )
    }
}

private struct RegionMapEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            String(localized: .regionMapEmptyTitle),
            systemSymbol: .map,
            description: Text(String(localized: .regionMapEmptyDescription)),
        )
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
                    kind: .display,
                    groups: snapshotLegendGroups,
                    selectedTitle: nil,
                    color: { group in
                        group.region.map { RegionStyle.fallbackStyle(for: $0).tint } ?? .gray
                    },
                    onSelect: { _ in },
                )
            }
            let coast = CoastalComparison()
            whereSnapshot(
                name: "LongIslandSound",
                configurations: [.init(device: .iPhone)],
                prepareForCapture: { try await coast.load() },
            ) {
                CoastMaps(prepared: coast)
            }
        }

        /// Fix the extent in both panels so a reviewer can see the same stretch of water.
        @MainActor @Observable fileprivate final class CoastalComparison {
            var maps: [RegionGeometryPurpose: RegionMapGeometry] = [:]

            func load() async throws {
                for purpose in RegionGeometryPurpose.allCases where maps[purpose] == nil {
                    maps[purpose] = try await Self.newYorkMap(for: purpose)
                }
            }

            @concurrent private static func newYorkMap(
                for purpose: RegionGeometryPurpose,
            ) async throws
                -> RegionMapGeometry
            {
                let outlines: [RegionOutline] = switch purpose {
                    case .display:
                        try await RegionGeometryCatalog.displayGeometry(for: [.newYork]).outlines
                    case .tracking:
                        RegionGeometryCatalog
                            .trackingOutlines(for: RegionAttributor(for: [.newYork]))
                }
                return RegionMapGeometry(outlines: outlines)
            }
        }

        private struct CoastMaps: View {
            let prepared: CoastalComparison
            private let frame = MKCoordinateRegion(
                center: .init(latitude: 40.91, longitude: -73.02),
                span: .init(latitudeDelta: 0.65, longitudeDelta: 1.35),
            )

            var body: some View {
                VStack {
                    ForEach(RegionGeometryPurpose.allCases, id: \.self) { purpose in
                        CoastalMapPanel(
                            purpose: purpose,
                            geometry: prepared.maps[purpose],
                            frame: frame,
                        )
                    }
                }
                .background(.background)
                .task {
                    do { try await prepared.load() }
                    catch is CancellationError { return }
                    catch { assertionFailure("Cannot load coastal comparison: \(error)") }
                }
            }
        }

        private struct CoastalMapPanel: View {
            let purpose: RegionGeometryPurpose
            let geometry: RegionMapGeometry?
            let frame: MKCoordinateRegion

            @Environment(\.regionStyles) private var regionStyles

            var body: some View {
                Text(WhereFormat.regionMapKind(purpose))
                if let geometry {
                    RegionOutlinesMap(
                        geometry: geometry,
                        selectedTitle: Region.newYork.localizedName,
                        frame: frame,
                        cameraPosition: .constant(.region(frame)),
                        color: { _ in regionStyles.style(for: .newYork).tint },
                    )
                }
            }
        }

        private static var snapshotLegendGroups: [RegionMapLegendGroup] {
            RegionCatalog.shared.entries.enumerated().map { index, entry in
                RegionMapLegendGroup(
                    title: entry.region.localizedName,
                    region: entry.region,
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
