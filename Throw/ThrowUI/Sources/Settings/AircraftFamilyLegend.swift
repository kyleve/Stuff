import SwiftUI
import ThrowCore

/// A compact, accessible key for the projection's silhouette vocabulary.
struct AircraftFamilyLegend: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.throwStylesheet) private var stylesheet

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), alignment: .leading), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: stylesheet.spacing.small) {
            ForEach(AircraftVisualFamily.allCases, id: \.self) { family in
                HStack(spacing: stylesheet.spacing.small) {
                    AircraftGlyphShape(family: family)
                        .fill(.primary)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(family.localizedTitle)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension AircraftVisualFamily {
    fileprivate var localizedTitle: LocalizedStringResource {
        switch self {
            case .heavyJet: .aircraftFamilyHeavyJet
            case .airliner: .aircraftFamilyAirliner
            case .regionalBusinessJet: .aircraftFamilyRegionalBusinessJet
            case .propeller: .aircraftFamilyPropeller
            case .helicopter: .aircraftFamilyHelicopter
            case .unknown: .aircraftFamilyUnknown
        }
    }
}
