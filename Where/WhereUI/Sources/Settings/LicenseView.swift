import CreditKit
import SnapshotKit
import SwiftUI

/// The full license notice for one credited work, pushed from Settings > About.
/// Permissive licenses require the notice verbatim, so it is rendered as plain
/// monospaced text, unreflowed and untruncated.
struct LicenseView: View {
    let credit: SoftwareCredit

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxLarge) {
                header
                notice
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(credit.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
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

    @ViewBuilder
    private var notice: some View {
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
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    LicenseView(
                        credit: PreviewSupport.sampleCredit(
                            noticeText: PreviewSupport.sampleNotice,
                        ),
                    )
                }
            }
            whereSnapshot(name: "NoNotice", configurations: .fullContentPhoneLightDark) {
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
