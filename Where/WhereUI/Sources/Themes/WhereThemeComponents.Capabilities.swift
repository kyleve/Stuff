extension WhereThemeComponents {
    /// Reject fields a native host cannot honor instead of accepting invisible overrides.
    func validateCapabilities() throws {
        for role in Role.allCases {
            guard let component = self[role] else { continue }
            let nativeSources: Set<WhereThemeNativeArtwork> = switch role {
                case .locations, .elsewhere:
                    [.rosette, .regionPattern]
                case .regularCard, .compactCard, .elsewhereCard, .summary, .welcome:
                    [.rosette, .microprint, .watermark, .stamp]
                case .forecastPanel:
                    [.rosette, .microprint, .stamp]
                case .privacy:
                    [.rosette, .stamp]
                case .year, .settings, .sheet, .calendarMonth, .timelineEntry, .section:
                    []
            }
            let authored = component.nativeArtwork ?? []
            guard Set(authored).count == authored.count,
                  Set(authored).isSubset(of: nativeSources)
            else { throw unsupported(role, "nativeArtwork") }
            switch role {
                case .locations, .elsewhere, .year, .settings, .sheet, .section:
                    if case .value = component.surface { throw unsupported(role, "surface") }
                    if case .value = component.heading { throw unsupported(role, "heading") }
                case .regularCard, .compactCard, .elsewhereCard, .summary, .forecastPanel,
                     .calendarMonth, .timelineEntry, .welcome, .privacy: break
            }
            for artwork in component.artwork ?? [] {
                if role == .section || role == .timelineEntry,
                   artwork.placement.plane != .interior || artwork.placement.outsets != .zero
                { throw unsupported(role, "artwork.placement") }
            }
        }
    }

    private func unsupported(_ role: Role, _ field: String) -> WhereThemeValidationError {
        .init(
            path: "components.\(role.rawValue).\(field)",
            reason: "Unsupported field for this native component",
        )
    }
}
