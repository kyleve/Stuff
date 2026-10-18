import SwiftUI

struct UpdateDetailRow<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.details
        let layout = style.arrangement == .stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: style.spacing))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: style.spacing))
        layout {
            Text(title)
                .font(style.labelFont)
                .foregroundStyle(.secondary)
            if style.arrangement == .horizontal {
                Spacer(minLength: 0)
            }
            content
                .font(style.valueFont)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
