import SFSafeSymbols
import SwiftUI
import ThrowCore

struct LayerCatalogRows: View {
    private let session: ThrowSession
    let experienceID: ProjectionExperienceID
    @State private var flightsEnabled: Bool
    @State private var geographyEnabled: Bool
    @Environment(\.throwStylesheet) private var stylesheet

    init(session: ThrowSession, experienceID: ProjectionExperienceID) {
        self.session = session
        self.experienceID = experienceID
        _flightsEnabled = State(initialValue: session.flightsEnabled)
        _geographyEnabled = State(initialValue: session.geographyEnabled)
    }

    var body: some View {
        ForEach(descriptors) { descriptor in
            layerRow(descriptor)
        }
        .onChange(of: flightsEnabled) { _, flightsEnabled in
            let preferences = session.airAndSpacePreferences
                .replacingFlightsEnabled(flightsEnabled)
            session.updateAirAndSpacePreferences(preferences)
        }
        .onChange(of: geographyEnabled) { _, geographyEnabled in
            let geography = session.airAndSpacePreferences.geography
                .replacingIsEnabled(geographyEnabled)
            let preferences = session.airAndSpacePreferences.replacingGeography(geography)
            session.updateAirAndSpacePreferences(preferences)
        }
        .onChange(of: session.flightsEnabled) { _, value in
            flightsEnabled = value
        }
        .onChange(of: session.geographyEnabled) { _, value in
            geographyEnabled = value
        }
    }

    private var descriptors: [AnyLayerDescriptor] {
        let layerIDs = ProjectionExperienceCatalog.standard[experienceID]?.layerIDs ?? []
        return layerIDs.compactMap { id in
            session.layerCatalog.descriptors.first { $0.id == id }
        }
    }

    @ViewBuilder private func layerRow(_ descriptor: AnyLayerDescriptor) -> some View {
        if descriptor.id == .flights {
            Toggle(isOn: $flightsEnabled) {
                layerLabel(descriptor.id)
            }
            .disabled(descriptor.availability.isEnabled == false)
        } else if descriptor.id == .geography {
            Toggle(isOn: $geographyEnabled) {
                HStack {
                    layerLabel(descriptor.id)
                    if session.projectionMode != .map {
                        Spacer()
                        Text(.layerMapOnly)
                            .foregroundStyle(.secondary)
                    } else if session.geographyLayerHealth == .unavailable {
                        Spacer()
                        Text(.layerUnavailable)
                            .foregroundStyle(stylesheet.status.failed)
                    }
                }
            }
            .disabled(
                descriptor.availability.isEnabled == false ||
                    session.projectionMode != .map,
            )
            .accessibilityHint(
                Text(session.geographyLayerHealth == .unavailable
                    && session.projectionMode == .map
                    ? .layerGeographyUnavailableHint
                    : .layerMapOnlyHint),
            )
        } else {
            LabeledContent {
                availabilityLabel(descriptor.availability)
            } label: {
                layerLabel(descriptor.id)
            }
        }
    }

    @ViewBuilder private func layerLabel(_ id: LayerID) -> some View {
        switch id {
            case .flights:
                Label(String(localized: .layerFlights), systemSymbol: .airplane)
            case .geography:
                Label(String(localized: .layerGeography), systemSymbol: .mapFill)
            case .stars:
                Label(String(localized: .layerStars), systemSymbol: .sparkles)
            case .satellites:
                Label(String(localized: .layerSatellites), systemSymbol: .globeAmericas)
            case .transitNetwork, .transitVehicles:
                Label {
                    Text(verbatim: id.rawValue)
                } icon: {
                    Image(systemSymbol: .circle)
                }
        }
    }

    @ViewBuilder private func availabilityLabel(_ availability: LayerAvailability) -> some View {
        switch availability {
            case .enabled:
                EmptyView()
            case .disabled:
                Text(.layerUnavailable).foregroundStyle(.secondary)
            case .planned:
                Text(.layerPlanned).foregroundStyle(.secondary)
        }
    }
}

extension LayerAvailability {
    fileprivate var isEnabled: Bool {
        if case .enabled = self { true } else { false }
    }
}
