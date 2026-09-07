import SFSafeSymbols
import SwiftUI

struct SourceChoiceLabel: View {
    let source: AircraftSourceChoice
    let selected: Bool

    var body: some View {
        HStack(alignment: .top) {
            Image(systemSymbol: selected ? .checkmarkCircleFill : .circle)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: LocalizedStringResource {
        switch source {
            case .adsbLol: .sourceAdsbLol
            case .readsb: .sourceReadsb
            case .adsbExchange: .sourceAdsbExchange
            case .flightradar24: .sourceFlightradar24
        }
    }

    private var detail: LocalizedStringResource {
        switch source {
            case .adsbLol: .sourceAdsbLolDescription
            case .readsb: .sourceReadsbDescription
            case .adsbExchange: .sourceAdsbExchangeDescription
            case .flightradar24: .sourceFlightradar24Description
        }
    }
}
