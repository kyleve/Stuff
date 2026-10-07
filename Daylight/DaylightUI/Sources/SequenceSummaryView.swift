import DaylightCore
import SwiftUI

struct SequenceSummaryView: View {
    let sequence: CaptureSequence
    var body: some View {
        VStack(alignment: .leading) {
            Text(sequence.event.id.kind.title).font(.headline)
            Text(sequence.event.date, format: .dateTime.month().day().hour().minute())
                .font(.subheadline)
            Text(.historyCount(sequence.images.count, sequence.slots.count))
            Text(.photosSavedCount(sequence.images.count(where: {
                if case .saved = $0.photos { true } else { false }
            }), sequence.images.count))
            if sequence.deliveries.isEmpty { Text(.publishingNone) }
            switch sequence.selection {
                case .pending: Text(.selectionPending)
                case .selected: Text(.selectionComplete)
                case let .failed(message): Text(message)
            }
            ForEach(sequence.deliveries) { delivery in
                switch delivery.state {
                    case .pending: Text(.publishingPending)
                    case let .retry(date, message): Text(message); Text(date, style: .relative)
                    case let .needsAttention(message): Text(message)
                    case let .delivered(receipt): Link(
                            String(localized: .publishingView),
                            destination: receipt.url,
                        )
                }
            }
        }
    }
}

#if DEBUG
    #Preview { SequenceSummaryView(sequence: DaylightPreviewSupport.sequence()) }
#endif
