import SFSafeSymbols
import SwiftUI
import ThrowCore

struct LayerCatalogRows: View {
    @Bindable var session: ThrowSession

    var body: some View {
        ForEach(session.layerCatalog.descriptors) { descriptor in
            layerRow(descriptor)
        }
    }

    @ViewBuilder private func layerRow(_ descriptor: AnyLayerDescriptor) -> some View {
        if descriptor.id == .flights {
            Toggle(isOn: $session.flightsEnabled) {
                layerLabel(descriptor.id)
            }
            .disabled(descriptor.availability.isEnabled == false)
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
