import CreditKit
import SnapshotKit
import SwiftUI

/// The full license notice for one credited work, pushed from Settings > About.
/// Permissive licenses require the notice verbatim, so it is rendered as plain
/// monospaced text, unreflowed and untruncated.
struct LicenseView: WhereScreen {
    let credit: SoftwareCredit

    @Environment(\.stylesheet) private var stylesheet

    var content: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxLarge) {
            LicenseHeader(credit: credit)
            LicenseNotice(credit: credit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(credit.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseHeader: View {
    let credit: SoftwareCredit

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(credit.license.name)
                .font(.headline)
            Text(credit.version)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = credit.homepageURL {
                Link(url.absoluteString, destination: url)
                    .font(.subheadline)
            }
        }
    }
}

private struct LicenseNotice: View {
    let credit: SoftwareCredit

    var body: some View {
        // The report carries the notice inline, so there is no file to fail to
        // load — an empty one would mean the generator wrote a credit without
        // text, which it refuses to do.
        if credit.license.text.isEmpty {
            Text(String(localized: .settingsAboutLicenseUnavailable))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text(credit.license.text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }
    }
}

#if DEBUG
    extension LicenseView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                ],
                measurementReadiness: .immediate,
            ) {
                let credit = PreviewSupport.sampleCredit(noticeText: PreviewSupport.sampleNotice)
                NavigationStack { LicenseView(credit: credit) }
            }
            whereSnapshot(
                name: "NoNotice",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                // The generator refuses to emit a credit without notice text, so
                // this is the state a hand-edited report would reach — worth an
                // image because it is the one case that renders no notice at all.
                NavigationStack {
                    LicenseView(credit: PreviewSupport.sampleCredit(noticeText: ""))
                }
            }
        }
    }

    #Preview {
        LicenseView.snapshotPreviews
    }
#endif

#if DEBUG
    extension LicenseView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            LicenseView.self,
            title: "License",
        )
    }
#endif
