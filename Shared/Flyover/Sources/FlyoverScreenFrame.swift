import SwiftUI

/// One overview card containing an inert rendered screen and live local controls.
struct FlyoverScreenFrame<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    var rendersContent = true

    var body: some View {
        VStack(spacing: 0) {
            FlyoverScreenHeader(screen: screen, model: model)

            Group {
                if rendersContent {
                    FlyoverScreenContent(screen: screen, model: model, isOverview: true)
                } else {
                    FlyoverScreenPlaceholder(screen: screen, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 440)
            .background(.black.opacity(0.08))

            Divider()

            FlyoverScreenControls(screen: screen, model: model)

            FlyoverRouteSummary(screen: screen, catalog: catalog)
        }
        .frame(width: FlyoverLayout<ScreenID>.cardSize.width)
        .frame(height: FlyoverLayout<ScreenID>.cardSize.height)
        .background(.background)
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.quaternary)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }
}

private struct FlyoverScreenPlaceholder<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(model.variant(for: screen).title)
                .font(.headline)
            Text("Move this frame toward the center, render it here, or inspect it full-screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Button("Render Preview", systemImage: "play.fill") {
                model.preview(screen)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(screen.title), preview paused")
    }
}
