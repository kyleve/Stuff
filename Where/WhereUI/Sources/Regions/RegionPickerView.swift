import MapKit
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

    @State private var mode: Mode = .map
    @State private var searchText = ""
    /// The loaded map geometry + a matching attributor for tap hit-testing. One
    /// `Result` so "loading" (`nil`), success, and failure can't be confused.
    @State private var mapData: Result<MapData, Error>?

    @Environment(\.stylesheet) private var stylesheet

    private static let logger = WhereLog.channel(.regionAttribution)

    var body: some View {
        VStack(spacing: stylesheet.spacing.medium) {
            modePicker

            Text(Strings.regionPickerSelectionCount(
                selected: model.selectionCount,
                max: PrimaryRegionSelectionModel.maxSelection,
            ))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.updatesFrequently)

            switch mode {
                case .map:
                    mapContent
                case .list:
                    listContent
            }
        }
        .task {
            if mapData == nil { await loadMap() }
        }
    }

    private var modePicker: some View {
        Picker(Strings.regionPickerModePicker, selection: $mode) {
            Text(Strings.regionPickerModeMap).tag(Mode.map)
            Text(Strings.regionPickerModeList).tag(Mode.list)
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
                    Strings.regionPickerLoadErrorTitle,
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
                    let tint = outline.region?.style.tint ?? .gray
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
        .accessibilityLabel(Strings.regionPickerMapAccessibility)
    }

    private func handleMapTap(at coordinate: CLLocationCoordinate2D, in data: MapData) {
        let region = data.attributor.region(at: Coordinate(coordinate))
        guard region != .other, model.available.contains(region) else { return }
        // Ignore an add that would exceed the cap so a tap can't silently fail
        // to register while still looking tappable.
        guard model.canToggle(region) else { return }
        model.toggle(region)
    }

    // MARK: - List

    private var filteredRegions: [Region] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.available }
        return model.available.filter {
            $0.localizedName.localizedCaseInsensitiveContains(query)
        }
    }

    private var listContent: some View {
        List {
            ForEach(filteredRegions, id: \.self) { region in
                Button {
                    model.toggle(region)
                } label: {
                    RegionPickerRow(
                        region: region,
                        isSelected: model.isSelected(region),
                    )
                }
                .disabled(!model.canToggle(region))
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: Strings.regionPickerSearchPrompt)
        .overlay {
            if filteredRegions.isEmpty {
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
            Self.logger.warning("Region picker failed to load map geometry: \(error)")
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

    var body: some View {
        HStack(spacing: stylesheet.spacing.medium) {
            Text(region.style.emoji)
                .accessibilityHidden(true)
            Text(region.localizedName)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(region.style.tint)
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
