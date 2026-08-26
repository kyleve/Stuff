import SFSafeSymbols
import SwiftUI
import ThrowCore

struct LayerCatalogRows: View {
    @Bindable var session: ThrowSession
    let experienceID: ProjectionExperienceID
    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        ForEach(descriptors) { descriptor in
            layerRow(descriptor)
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
            Toggle(isOn: $session.flightsEnabled) {
                layerLabel(descriptor.id)
            }
            .disabled(descriptor.availability.isEnabled == false)
        } else if descriptor.id == .geography {
            Toggle(isOn: $session.geographyEnabled) {
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
        if id == .flights {
            Label(String(localized: .layerFlights), systemSymbol: .airplane)
        } else if id == .geography {
            Label(String(localized: .layerGeography), systemSymbol: .mapFill)
        } else if id == .stars {
            Label(String(localized: .layerStars), systemSymbol: .sparkles)
        } else if id == .satellites {
            Label(String(localized: .layerSatellites), systemSymbol: .globeAmericas)
        } else {
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
            case let .disabled(explanation):
                Text(verbatim: explanation).foregroundStyle(.secondary)
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
