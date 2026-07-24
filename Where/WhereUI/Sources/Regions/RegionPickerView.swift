import MapKit
import PeriscopeCore
import RegionKit
import SwiftUI
import WhereCore

/// Picks the user's primary regions — up to `PrimaryRegionSelectionModel.maxSelection`
/// — either by tapping states on a map or from a searchable list, switched via a
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

    @State private var mode: Mode = .list
    @State private var searchText = ""
    /// Bumped whenever a map tap is ignored because the selection is full, to
    /// drive the warning haptic.
    @State private var capacityBumps = 0
    /// The loaded map geometry + a matching attributor for tap hit-testing. One
    /// `Result` so "loading" (`nil`), success, and failure can't be confused.
    @State private var mapData: Result<MapData, Error>?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private static let logger = WhereLog.session(RegionPickerViewLog.self)

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
        // so a user who stays in the default List never pays the ~52-file parse.
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
                    systemImage: "map",
                    description: Text(error.localizedDescription),
                )
            case let .some(.success(data)):
                map(data)
        }
    }

    private func map(_ data: MapData) -> some View {
        let style = stylesheet.regionPicker
        return MapReader { proxy in
            Map(initialPosition: .region(unitedStatesRegion)) {
                ForEach(data.outlines) { outline in
                    let selected = outline.region.map(model.isSelected) ?? false
                    let tint = outline.region.map { regionStyles.style(for: $0).tint } ?? .gray
                    MapPolygon(coordinates: outline.coordinates.clLocationCoordinates)
                        .foregroundStyle(tint.opacity(
                            selected ? style.selectedFillOpacity : style.unselectedFillOpacity,
                        ))
                        .stroke(
                            tint.opacity(
                                selected
                                    ? style.selectedStrokeOpacity
                                    : style.unselectedStrokeOpacity,
                            ),
                            lineWidth: selected
                                ? style.selectedStrokeWidth
                                : style.unselectedStrokeWidth,
                        )
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                handleMapTap(at: coordinate, in: data)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: style.mapCornerRadius, style: .continuous))
        .padding(.horizontal, stylesheet.spacing.large)
        .accessibilityLabel(String(localized: .regionPickerMapAccessibility))
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
        .searchable(text: $searchText, prompt: String(localized: .regionPickerSearchPrompt))
        .overlay {
            if isSearching, filteredRegions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Loading

    /// The loaded US geometry plus the attributor built from the same regions,
    /// so a map tap resolves to exactly the regions the outlines drew.
    struct MapData {
        let outlines: [RegionOutline]
        let attributor: RegionAttributor
    }

    private func loadMap() async {
        let regions = model.available
        do {
            // Building the attributor parses every offered region's GeoJSON, so
            // keep it off the main actor; the outline read is then cheap.
            let attributor = await Task
                .detached(priority: .userInitiated) { RegionAttributor(for: regions) }
                .value
            let outlines = try await RegionGeometryCatalog.outlines(
                for: .attribution,
                attributor: attributor,
            )
            guard !Task.isCancelled else { return }
            mapData = .success(MapData(outlines: outlines, attributor: attributor))
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the failure observable in both the UI (error state) and the
            // logs rather than showing a blank map.
            Self.logger(attachments: [.error(error, name: "geometry-error")]) {
                .mapGeometryLoadFailed(description: error.localizedDescription)
            }
            mapData = .failure(error)
        }
    }

    /// A camera framed on the contiguous US, a sensible default for a US-only
    /// picker (the user can pan to Alaska/Hawaii). Built from the stylesheet's
    /// raw degrees so the token stays MapKit-free.
    private var unitedStatesRegion: MKCoordinateRegion {
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
                Image(systemName: "checkmark")
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
    #Preview("Empty") {
        RegionPickerView(model: PrimaryRegionSelectionModel())
            .whereBroadwayRoot()
    }

    #Preview("Seeded") {
        RegionPickerView(model: PreviewSupport.primaryRegionSelectionModel())
            .whereBroadwayRoot()
    }
#endif
