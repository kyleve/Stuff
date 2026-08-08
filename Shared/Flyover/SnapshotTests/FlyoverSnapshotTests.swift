@testable import Flyover
import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct FlyoverSnapshotTests {
    @Test func canvasAndList() async {
        let catalog = Self.catalog()
        await assertSnapshots(
            of: FlyoverView(catalog: catalog),
            named: "FlyoverCanvas",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPadFullContent],
                colorSchemes: [.light, .dark],
            ),
            // Canvas previews load serially, so a cold CI host can still be resolving
            // the visible screen trees after the default settling budget.
            settle: .settledAtLeast(minDuration: 1.5),
        )

        await assertSnapshots(
            of: FlyoverView(catalog: catalog),
            named: "FlyoverCompact",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhoneFullContent],
            ),
        )

        let model = FlyoverModel(catalog: catalog)
        model.viewMode = .list
        await assertSnapshots(
            of: FlyoverOverview(catalog: catalog, model: model)
                .safeAreaInset(edge: .bottom) {
                    FlyoverControlBar(catalog: catalog, model: model)
                },
            named: "FlyoverList",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPadFullContent],
            ),
        )
    }

    private static func catalog() -> FlyoverCatalog<SnapshotScreen> {
        FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("app"),
                    title: "App flow",
                    root: .home,
                    screens: [
                        screen(.home, title: "Home", color: .blue),
                        screen(.detail, title: "Detail", color: .indigo),
                        screen(.editor, title: "Editor", color: .purple),
                    ],
                ),
                FlyoverGroup(
                    id: FlyoverGroupID("components"),
                    title: "Components",
                    root: .widget,
                    screens: [
                        FlyoverScreen(
                            id: .widget,
                            title: "Widget",
                            viewport: .fixed(CGSize(width: 338, height: 158)),
                            navigationContainer: .none,
                            variants: [
                                FlyoverVariant(
                                    id: FlyoverVariantID("default"),
                                    title: "Default",
                                ) {
                                    SnapshotCard(
                                        title: "Today",
                                        subtitle: "California · 29 days",
                                        color: .orange,
                                    )
                                },
                            ],
                        ),
                    ],
                ),
            ],
            transitions: [
                FlyoverTransition(from: .home, to: .detail, kind: .push),
                FlyoverTransition(from: .detail, to: .editor, kind: .modal),
            ],
        )
    }

    private static func screen(
        _ id: SnapshotScreen,
        title: String,
        color: Color,
    ) -> FlyoverScreen<SnapshotScreen> {
        FlyoverScreen(
            id: id,
            title: title,
            variants: [
                FlyoverVariant(
                    id: FlyoverVariantID("populated"),
                    title: "Populated",
                ) {
                    List {
                        SnapshotCard(
                            title: title,
                            subtitle: "Populated state",
                            color: color,
                        )
                        SnapshotCard(
                            title: "Secondary",
                            subtitle: "Additional content",
                            color: color.opacity(0.75),
                        )
                    }
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add", systemImage: "plus", action: {})
                        }
                    }
                },
                FlyoverVariant(
                    id: FlyoverVariantID("empty"),
                    title: "Empty",
                ) {
                    ContentUnavailableView(
                        "No \(title)",
                        systemImage: "rectangle.stack",
                    )
                },
            ],
        )
    }
}

private enum SnapshotScreen: Hashable {
    case home
    case detail
    case editor
    case widget
}

private struct SnapshotCard: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
