import Foundation
import SwiftUI

struct LocationDetailView: View {
    let accuracyMeters: Double
    let acceptedAt: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.throwDateProvider) private var dateProvider

    var body: some View {
        Text(
            Measurement(value: accuracyMeters, unit: UnitLength.meters),
            format: .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0)),
            ),
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        Text(
            verbatim: RelativeDatePresentation.string(
                for: acceptedAt,
                relativeTo: dateProvider.now(),
                locale: locale,
                calendar: calendar,
            ),
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
