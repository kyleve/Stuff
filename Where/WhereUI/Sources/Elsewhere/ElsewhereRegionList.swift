import SFSafeSymbols
import SwiftUI

struct ElsewhereRegionList: View {
    let content: ElsewhereModel.Content
    let report: YearReportModel
    let model: ElsewhereModel
    let failureMessage: String?
    let retry: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xLarge) {
                if let failureMessage {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                        Label(failureMessage, systemSymbol: .exclamationmarkIcloud)
                        ElsewhereRetryButton(retry: retry)
                    }
                }
                if content.regions.isEmpty {
                    EmptyElsewhere()
                } else {
                    ElsewhereRegionCards(content: content, report: report, model: model)
                }
            }
            .padding()
            .whereContentRoot()
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("where_elsewhere_list")
    }
}

private struct ElsewhereRegionCards: View {
    let content: ElsewhereModel.Content
    let report: YearReportModel
    let model: ElsewhereModel
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        GlassEffectContainer(spacing: stylesheet.spacing.large) {
            VStack(spacing: stylesheet.spacing.large) {
                ForEach(content.regions) { item in
                    ElsewhereRegionLink(item: item, content: content, report: report, model: model)
                }
            }
        }
    }
}

private struct EmptyElsewhere: View {
    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .secondaryEmptyTitle), systemSymbol: .globeAmericas)
        } description: {
            Text(String(localized: .secondaryEmptyDescription))
        }
    }
}

#if DEBUG
    #Preview("Visited regions") {
        ElsewhereView.snapshotPreviews
    }
#endif
