#if DEBUG
    import Foundation
    import Observation

    /// Root-owned state for the DEBUG card designer. Drafts persist across
    /// launches, while the app-wide override deliberately starts disabled.
    @MainActor @Observable
    final class CardDesignerModel {
        enum Section: CaseIterable {
            case card
            case typography
            case entryStamp
            case regionArtwork
            case microprint
            case rosettes
            case sheen
            case glassAndInk
            case shadows
        }

        var configuration: CardDesignerConfiguration {
            didSet {
                guard oldValue != configuration else { return }
                persist()
            }
        }

        /// Session-only by design: a debug launch should never silently boot
        /// with experimental cards active outside the studio.
        var appliesToApp = false
        var persistenceError: String?

        var isShowingPersistenceError: Bool {
            get { persistenceError != nil }
            set {
                guard newValue == false else { return }
                persistenceError = nil
            }
        }

        private let store: UserDefaults
        private let key: String

        init(store: UserDefaults, key: String) {
            self.store = store
            self.key = key
            do {
                configuration = try Self.load(from: store, key: key)
            } catch {
                configuration = .standard
                persistenceError = error.localizedDescription
            }
        }

        init(configuration: CardDesignerConfiguration) {
            store = .standard
            key = "where.debug.card-designer.preview"
            self.configuration = configuration
            appliesToApp = false
        }

        func resetAll() {
            configuration = .standard
        }

        func reset(_ variant: CardDesignerConfiguration.Variant) {
            configuration[variant] = CardDesignerConfiguration.standard[variant]
        }

        func resetShared() {
            configuration.shared = CardDesignerConfiguration.standard.shared
        }

        func reset(_ section: Section, variant: CardDesignerConfiguration.Variant) {
            let standard = CardDesignerConfiguration.standard
            var card = configuration[variant]
            let standardCard = standard[variant]
            switch section {
                case .card:
                    card.cornerRadius = standardCard.cornerRadius
                    card.padding = standardCard.padding
                    card.contentSpacing = standardCard.contentSpacing
                    card.progressBarHeight = standardCard.progressBarHeight
                    card.watermarkFontSize = standardCard.watermarkFontSize
                    card.watermarkOffset = standardCard.watermarkOffset
                case .typography:
                    card.regionNameTypography = standardCard.regionNameTypography
                    card.regionNameTracking = standardCard.regionNameTracking
                    card.heroNumberTypography = standardCard.heroNumberTypography
                    card.dayUnitTypography = standardCard.dayUnitTypography
                case .entryStamp:
                    card.entryStamp = standardCard.entryStamp
                case .regionArtwork:
                    card.usesRegionShape = standardCard.usesRegionShape
                    card.regionShape = standardCard.regionShape
                case .microprint:
                    card.regionShape.securityBorder = standardCard.regionShape.securityBorder
                case .rosettes:
                    card.rosette = standardCard.rosette
                    configuration.shared.primaryRosetteOpacity = standard.shared
                        .primaryRosetteOpacity
                    configuration.shared.secondaryRosetteOpacity = standard.shared
                        .secondaryRosetteOpacity
                case .sheen:
                    card.sheen = standardCard.sheen
                case .glassAndInk:
                    resetShared()
                    return
                case .shadows:
                    card.glow = standardCard.glow
                    card.lift = standardCard.lift
            }
            configuration[variant] = card
        }

        func dismissPersistenceError() {
            persistenceError = nil
        }

        func jsonData() throws -> Data {
            try Self.encoder.encode(configuration)
        }

        private func persist() {
            do {
                try store.set(jsonData(), forKey: key)
                persistenceError = nil
            } catch {
                persistenceError = error.localizedDescription
            }
        }

        private static func load(
            from store: UserDefaults,
            key: String,
        ) throws -> CardDesignerConfiguration {
            guard let data = store.data(forKey: key) else { return .standard }
            let configuration = try JSONDecoder().decode(CardDesignerConfiguration.self, from: data)
            guard configuration.schemaVersion == CardDesignerConfiguration.currentSchemaVersion
            else {
                throw CardDesignerPersistenceError.unsupportedSchema(configuration.schemaVersion)
            }
            return configuration
        }

        private static var encoder: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return encoder
        }
    }

    private enum CardDesignerPersistenceError: LocalizedError {
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
                case let .unsupportedSchema(version):
                    "Card designer schema \(version) is not supported by this build."
            }
        }
    }
#endif
