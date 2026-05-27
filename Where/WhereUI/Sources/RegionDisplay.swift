import SwiftUI
import WhereCore

extension Region {
    /// Swatch color used to distinguish regions in the report UI. The
    /// switch is exhaustive (no `default`) so adding a `Region` case is
    /// a compile error here until a color is chosen — matching the
    /// "adding a region is intentionally a compile error" convention in
    /// `WhereCore`.
    var displayColor: Color {
        switch self {
            case .california: .orange
            case .newYork: .blue
            case .canada: .red
            case .europeanUnion: .indigo
            case .other: .gray
        }
    }
}

/// A colored swatch plus the region's localized name. Used in the
/// per-region totals rows.
struct RegionLabel: View {
    let region: Region

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(region.displayColor)
                .frame(width: 10, height: 10)
            Text(region.localizedName)
        }
    }
}
