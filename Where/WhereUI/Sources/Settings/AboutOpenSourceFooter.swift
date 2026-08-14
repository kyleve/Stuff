import Foundation
import SwiftUI

/// A compact passport-style sign-off linking the About screen to Where's source.
struct AboutOpenSourceFooter: View {
    static let projectURL = URL(string: "https://github.com/kyleve/Stuff")!

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Link(destination: Self.projectURL) {
            let style = stylesheet.openSourceStamp
            let ink = style.ink
            let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: style.contentSpacing) {
                        HStack {
                            PassportSeal(
                                systemSymbol: .chevronLeftForwardslashChevronRight,
                                tint: .accentColor.opacity(ink.sealOpacity),
                            )
                            Spacer(minLength: 0)
                            Image(systemSymbol: .arrowUpRight)
                                .foregroundStyle(.tint.opacity(ink.accessoryOpacity))
                                .accessibilityHidden(true)
                        }
                        AboutOpenSourceStampText()
                    }
                } else {
                    HStack(spacing: style.contentSpacing) {
                        PassportSeal(
                            systemSymbol: .chevronLeftForwardslashChevronRight,
                            tint: .accentColor.opacity(ink.sealOpacity),
                        )
                        AboutOpenSourceStampText()
                        Spacer(minLength: 0)
                        Image(systemSymbol: .arrowUpRight)
                            .foregroundStyle(.tint.opacity(ink.accessoryOpacity))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SecurityPrintRosette(
                    tint: .accentColor,
                    wobble: style.rosette.wobble,
                    lineWidth: style.rosette.lineWidth,
                    primaryRingSpacing: style.rosette.primaryRingSpacing,
                    secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                    primaryOpacity: ink.primaryRosetteOpacity,
                    secondaryOpacity: ink.secondaryRosetteOpacity,
                )
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    .tint.opacity(ink.outlineOpacity),
                    lineWidth: style.outlineWidth,
                )
            }
            .contentShape(shape)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
    #Preview {
        Form {
            AboutOpenSourceFooter()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .whereBroadwayRoot()
    }
#endif
