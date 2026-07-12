import LogKit
import MapKit
import RegionKit
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
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription),
                )
            case let .some(.success(loaded)) where loaded.isEmpty:
                ContentUnavailableView(
                    String(localized: .regionMapEmptyTitle),
                    systemImage: "map",
                    description: Text(.regionMapEmptyDescription),
                )
            case let .some(.success(loaded)):
                VStack(spacing: 0) {
                    map(for: visibleOutlines(in: loaded))
                    legend(for: loaded)
                }
        }
    }

    private func map(for outlines: [RegionOutline]) -> some View {
        Map(position: $cameraPosition) {
            ForEach(outlines) { outline in
                MapPolygon(coordinates: outline.coordinates.clLocationCoordinates)
                    .foregroundStyle(color(for: outline).opacity(0.25))
                    .stroke(color(for: outline), lineWidth: 1.5)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(maxHeight: .infinity)
        .accessibilityLabel(String(localized: .regionMapMapAccessibility))
    }

    private func legend(for loaded: [RegionOutline]) -> some View {
        List {
            Section {
                if selectedTitle != nil {
                    Button(.regionMapShowAll) { select(nil) }
                }
                ForEach(legendGroups(for: loaded)) { group in
                    Button {
                        select(group.title == selectedTitle ? nil : group.title)
                    } label: {
                        legendRow(group)
                    }
                    .tint(.primary)
                }
            } header: {
                Text(.regionMapLegendHeader)
            } footer: {
                Text(WhereFormat.regionMapKindFooter(kind))
            }
        }
        .frame(height: stylesheet.regionMap.height)
    }

    private func legendRow(_ group: LegendGroup) -> some View {
        HStack(spacing: stylesheet.spacing.large) {
            Circle()
                .fill(color(forTitle: group.title, region: group.region))
                // Developer legend swatch — a fixed dev-tool size, not a themed token.
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(group.title)
            Spacer()
            if group.outlineCount > 1 {
                Text("\(group.outlineCount)")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if group.title == selectedTitle {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
    }

    // MARK: - Data

    private func load() async {
        outlines = nil
        selectedTitle = nil
        do {
            let loaded = try await RegionGeometryCatalog.outlines(for: kind)
            guard !Task.isCancelled else { return }
            outlines = .success(loaded)
            reframe(to: loaded)
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the failure observable in both the UI (the `.failure`
            // state renders an error) and the logs, rather than silently
            // showing an empty map.
            RegionLog.channel(.geometryCatalog)
                .warning("Region map viewer failed to load \(kind.rawValue) geometry: \(error)")
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
    private func legendGroups(for loaded: [RegionOutline]) -> [LegendGroup] {
        var groups: [LegendGroup] = []
        var indexByTitle: [String: Int] = [:]
        for outline in loaded {
            if let index = indexByTitle[outline.title] {
                groups[index].outlineCount += 1
            } else {
                indexByTitle[outline.title] = groups.count
                groups.append(LegendGroup(
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

    /// A camera framed to `outlines` (with a little padding). Latitude
    /// comes from `BoundingBox` (latitude never wraps); longitude from
    /// `LongitudeSpan`, which is antimeridian-aware — so filtering to
    /// Alaska frames the Aleutians tightly instead of zooming out to the
    /// whole globe (its rings span ~+172° across 180° to ~−130°). Falls
    /// back to `.automatic` when there's nothing to show.
    private static func cameraPosition(enclosing outlines: [RegionOutline]) -> MapCameraPosition {
        guard let box = BoundingBox.enclosing(outlines),
              let longitude = LongitudeSpan.enclosing(
                  outlines.lazy.flatMap { $0.coordinates.lazy.map(\.longitude) },
              )
        else { return .automatic }
        let center = CLLocationCoordinate2D(
            latitude: (box.minLatitude + box.maxLatitude) / 2,
            longitude: longitude.center,
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((box.maxLatitude - box.minLatitude) * 1.3, 1), 170),
            longitudeDelta: min(max(longitude.degrees * 1.3, 1), 350),
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Color

    private func color(for outline: RegionOutline) -> Color {
        color(forTitle: outline.title, region: outline.region)
    }

    /// A region keeps its `RegionStyle` tint; an untagged source feature
    /// gets a stable color derived from its title so the same feature is
    /// always the same hue across launches.
    private func color(forTitle title: String, region: Region?) -> Color {
        if let region { return region.style.tint }
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

/// One feature in the legend: its title, the `Region` it maps to (if any,
/// for the swatch color), and how many sub-polygons it contributed.
private struct LegendGroup: Identifiable {
    let title: String
    let region: Region?
    var outlineCount: Int

    var id: String {
        title
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            RegionMapView()
        }
    }
#endif
