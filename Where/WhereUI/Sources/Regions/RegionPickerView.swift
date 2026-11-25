import MapKit
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Picks the user's primary regions — up to `PrimaryRegionSelectionModel.maxSelection`
/// — either by tapping regions on a map or from a searchable list, switched via a
/// top-aligned segmented control. Selection lives in the shared
/// ``PrimaryRegionSelectionModel``; this view only reads/toggles it. Used inside
/// onboarding and the Settings region editor.
struct RegionPickerView: View {
    @Bindable var model: PrimaryRegionSelectionModel

    /// Map vs list, the two ways to pick.
    enum Mode: String, CaseIterable, Hashable {
        case map
        case list
    }

    @State private var mode: Mode
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var searchText = ""
    /// Bumped whenever a map tap is ignored because the selection is full, to
    /// drive the warning haptic.
    @State private var capacityBumps = 0
    /// The loaded map geometry + a matching attributor for tap hit-testing. One
    /// `Result` so "loading" (`nil`), success, and failure can't be confused.
    @State private var mapData: Result<MapData, Error>?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    private static let logger = WhereLog.session(RegionPickerViewLog.self)

    init(model: PrimaryRegionSelectionModel, initialMode: Mode = .list) {
        self.model = model
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: stylesheet.spacing.medium) {
            modePicker

            VStack(spacing: stylesheet.spacing.xSmall) {
                Text(WhereFormat.regionPickerSelectionCount(
                    selected: model.selectionCount,
                    max: PrimaryRegionSelectionModel.maxSelection,
                ))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)

                if model.isAtCapacity {
                    Text(WhereFormat
                        .regionPickerAtCapacity(max: PrimaryRegionSelectionModel.maxSelection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .animation(stylesheet.motion.captionFade, value: model.isAtCapacity)

            switch mode {
                case .map:
                    mapContent
                case .list:
                    listContent
            }
        }
        // A capped tap on the map is otherwise silent (unlike the list, which
        // disables rows), so signal it with a warning haptic.
        .sensoryFeedback(.warning, trigger: capacityBumps)
        // Parse region geometry lazily — only once Map mode is actually shown,
        // so a user who stays in the default List never pays the geometry parse.
        .task(id: mode) {
            guard mode == .map, mapData == nil else { return }
            await loadMap()
        }
        // Log View Mode: reveal an inspect badge for region-picker events (map
        // geometry load). A no-op in release.
        .debugLogInspectable(WhereLog.session(RegionPickerViewLog.self))
    }

    private var modePicker: some View {
        Picker(String(localized: .regionPickerModePicker), selection: $mode) {
            Text(String(localized: .regionPickerModeMap)).tag(Mode.map)
            Text(String(localized: .regionPickerModeList)).tag(Mode.list)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, stylesheet.spacing.large)
        .whereContentRoot()
    }

    // MARK: - Map

    @ViewBuilder
    private var mapContent: some View {
        switch mapData {
            case .none:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .some(.failure(error)):
                ContentUnavailableView(
                    String(localized: .regionPickerLoadErrorTitle),
                    systemSymbol: .map,
                    description: Text(error.localizedDescription),
                )
            case let .some(.success(data)):
                map(data)
        }
    }

    private func map(_ data: MapData) -> some View {
        let style = stylesheet.regionPicker
        return Group {
            if isCapturingSnapshot {
                RegionMapCanvas(
                    geometry: data.geometry,
                    selectedTitle: nil,
                    region: northAmericanRegion,
                    style: overlayStyle(for:),
                )
            } else {
                MapReader { proxy in
                    RegionPolygonMap(
                        geometry: data.geometry,
                        position: $mapPosition,
                    ) { outline, polygon in
                        let appearance = overlayStyle(for: outline)
                        MapPolygon(polygon)
                            .foregroundStyle(appearance.fill)
                            .stroke(appearance.stroke, lineWidth: appearance.lineWidth)
                    }
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        handleMapTap(at: coordinate, in: data)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: style.mapCornerRadius, style: .continuous))
        .padding(.horizontal, stylesheet.spacing.large)
        .accessibilityLabel(String(localized: .regionPickerMapAccessibility))
    }

    private func overlayStyle(for outline: RegionOutline) -> RegionMapOverlayStyle {
        let style = stylesheet.regionPicker
        let selected = outline.region.map(model.isSelected) == true
        let tint = outline.region.map { regionStyles.style(for: $0).tint } ?? .gray
        return RegionMapOverlayStyle(
            fill: tint.opacity(selected ? style.selectedFillOpacity : style.unselectedFillOpacity),
            stroke: tint
                .opacity(selected ? style.selectedStrokeOpacity : style.unselectedStrokeOpacity),
            lineWidth: selected ? style.selectedStrokeWidth : style.unselectedStrokeWidth,
        )
    }

    private func handleMapTap(at coordinate: CLLocationCoordinate2D, in data: MapData) {
        let region = data.attributor.region(at: Coordinate(coordinate))
        guard region != .other, model.available.contains(region) else { return }
        guard model.canToggle(region) else {
            // At capacity and tapping a new region — the list disables its rows
            // to show this, but the map has no such affordance, so buzz instead
            // of silently ignoring the tap.
            capacityBumps += 1
            return
        }
        model.toggle(region)
    }

    // MARK: - List

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredRegions: [Region] {
        guard isSearching else { return model.available }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return model.available.filter {
            $0.localizedName.localizedCaseInsensitiveContains(query)
        }
    }

    private func regionRow(_ region: Region) -> some View {
        Button {
            model.toggle(region)
        } label: {
            RegionPickerRow(region: region, isSelected: model.isSelected(region))
        }
        .disabled(!model.canToggle(region))
    }

    private var listContent: some View {
        List {
            // Grouped (Settings) shows your-regions / used-this-year / more via
            // the shared sections; onboarding and any active search fall back to
            // a flat list.
            if model.isGrouped, !isSearching {
                GroupedRegionSections(grouping: model.grouping, row: regionRow)
            } else {
                ForEach(filteredRegions, id: \.self, content: regionRow)
            }
        }
        .listStyle(.plain)
        .whereFormRoot()
        .searchable(text: $searchText, prompt: String(localized: .regionPickerSearchPrompt))
        .overlay {
            if isSearching, filteredRegions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Loading

    /// The drawable geometry plus the attributor built from the same regions,
    /// so a map tap resolves to exactly the regions the outlines drew.
    struct MapData {
        let geometry: RegionMapGeometry
        let attributor: RegionAttributor

        @concurrent init(regions: [Region]) async throws {
            try Task.checkCancellation()
            attributor = RegionAttributor(for: regions)
            try Task.checkCancellation()
            let outlines = try await RegionGeometryCatalog.outlines(
                for: .attribution,
                attributor: attributor,
            )
            try Task.checkCancellation()
            geometry = RegionMapGeometry(outlines: outlines)
        }
    }

    private func loadMap() async {
        let regions = model.available
        do {
            // Building the attributor reads every offered region's geometry, so
            // keep it off the main actor; the outline read is then cheap.
            let data = try await MapData(regions: regions)
            guard !Task.isCancelled else { return }
            mapPosition = .region(northAmericanRegion)
            mapData = .success(data)
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the failure observable in both the UI (error state) and the
            // logs rather than showing a blank map.
            Self.logger.mapGeometryLoadFailed(
                error: .restricted(.errorDetails, error),
            )
            mapData = .failure(error)
        }
    }

    /// Start with both countries in reach. The list also offers offshore jurisdictions.
    private var northAmericanRegion: MKCoordinateRegion {
        let style = stylesheet.regionPicker
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: style.mapCenterLatitude,
                longitude: style.mapCenterLongitude,
            ),
            span: MKCoordinateSpan(
                latitudeDelta: style.mapSpanLatitude,
                longitudeDelta: style.mapSpanLongitude,
            ),
        )
    }
}

/// A selectable region row: the region's emoji + name with a trailing checkmark
/// when picked.
private struct RegionPickerRow: View {
    let region: Region
    let isSelected: Bool

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let style = regionStyles.style(for: region)
        return HStack(spacing: stylesheet.spacing.medium) {
            Text(style.emoji)
                .accessibilityHidden(true)
            Text(region.localizedName)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemSymbol: .checkmark)
                    .fontWeight(.semibold)
                    .foregroundStyle(style.tint)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
    extension RegionPickerView: SnapshotProviding {
        private init(model: PrimaryRegionSelectionModel, prepared: MapData) {
            self.init(model: model, initialMode: .map)
            _mapData = State(initialValue: .success(prepared))
        }

        @MainActor @Observable fileprivate final class SnapshotGeometry {
            var map: MapData?
        }

        private struct SnapshotMap: View {
            let model: PrimaryRegionSelectionModel
            let prepared: SnapshotGeometry
            var body: some View {
                if let map = prepared.map { RegionPickerView(model: model, prepared: map) }
            }
        }

        static var snapshots: [SnapshotCase] {
            let model = PrimaryRegionSelectionModel()
            model.toggle(.california)
            model.toggle(.ontario)
            let prepared = SnapshotGeometry()
            return [
                whereSnapshot(
                    name: "AvailableRegions",
                    configurations: [.init(device: .iPhoneFullContent)],
                ) {
                    NavigationStack { RegionPickerView(model: model) }
                },
                whereSnapshot(
                    name: "NorthAmericanMap",
                    configurations: [.init(device: .iPhone)],
                    prepareForCapture: {
                        prepared.map = try await MapData(regions: model.available)
                    },
                ) {
                    NavigationStack { SnapshotMap(model: model, prepared: prepared) }
                },
            ]
        }
    }
#endif

#if DEBUG
    #Preview("Empty") {
        RegionPickerView(model: PrimaryRegionSelectionModel())
            .whereBroadwayRoot()
    }

    #Preview("Seeded") {
        RegionPickerView(model: PreviewSupport.primaryRegionSelectionModel())
            .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension RegionPickerView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(RegionPickerView.self) { id, world in
            .init(
                id: id,
                title: "Region Picker",
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "list",
                        title: "List",
                        world: world,
                    ) {
                        RegionPickerView(
                            model: PreviewSupport.primaryRegionSelectionModel(),
                            initialMode: .list,
                        )
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "map",
                        title: "Map",
                        world: world,
                    ) {
                        RegionPickerView(
                            model: PreviewSupport.primaryRegionSelectionModel(),
                            initialMode: .map,
                        )
                    },
                ],
            )
        }
    }
#endif
