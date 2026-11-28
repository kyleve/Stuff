import SwiftUI
import WhereCore

struct RegionCardProgress: View {
    let recordedDays: Int
    let estimatedDays: DayBounds?
    let yearLength: Int
    let barHeight: CGFloat
    let contentTint: Color
    let securityPrintTint: Color
    let estimatedProgressOpacity: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        if let estimatedFraction {
                            Capsule()
                                .fill(securityPrintTint.opacity(
                                    estimatedProgressOpacity,
                                ))
                                .frame(width: proxy.size.width * estimatedFraction)
                            if let estimatedDays, !estimatedDays.isExact {
                                Capsule()
                                    .fill(securityPrintTint.opacity(
                                        estimatedProgressOpacity,
                                    ))
                                    .frame(width: proxy.size
                                        .width * fraction(for: estimatedDays.lower))
                                Rectangle()
                                    .fill(securityPrintTint)
                                    .frame(width: barHeight / 3)
                                    .offset(x: proxy.size
                                        .width * fraction(for: estimatedDays.lower))
                            }
                        }
                        Capsule()
                            .fill(contentTint)
                            .frame(width: proxy.size.width * recordedFraction)
                    }
                    .frame(width: proxy.size.width, height: barHeight, alignment: .leading)
                    .clipShape(.capsule)
                }
            }
            .frame(height: barHeight)
            .accessibilityHidden(true)
    }

    private var recordedFraction: Double {
        fraction(for: recordedDays)
    }

    private var estimatedFraction: Double? {
        estimatedDays.map { fraction(for: $0.upper) }
    }

    private func fraction(for days: Int) -> Double {
        guard yearLength > 0 else { return 0 }
        return min(1, max(0, Double(days) / Double(yearLength)))
    }
}

#if DEBUG
    #Preview("Region card") {
        RegionSummaryCard(
            regionDays: RegionDays(region: .california, days: 148),
            caption: "Home base",
            year: 2026,
        )
        .whereBroadwayRoot()
    }
#endif
