import SwiftUI

/// How a snapshot case's content reaches its capture-ready state.
public enum SnapshotSettle: Sendable {
    /// Wait for the rendered content to quiesce before capture, so `.task`-driven
    /// async loads resolve first. The safe default.
    case settled
    /// The content is fully renderable after a layout pass: skip the settle loop.
    /// A single task yield still runs, so a `.task` body that merely sets state
    /// synchronously gets one shot — but nothing that needs real time will load.
    case immediate
}

/// A named group of snapshot variants for a component: the configurations to
/// render, and the content to render under each.
///
/// It is also a `View`, so it renders a labeled, scrollable cutsheet of its
/// variants inside a `#Preview` — the same content the snapshot tests capture.
/// Accessibility variants are excluded from that preview (see
/// ``previewConfigurations``); they only render as tests.
public struct SnapshotCase: Identifiable {
    /// The case name — groups a component's variants and prefixes their
    /// reference-image identifiers.
    public let name: String
    /// The configurations (appearance/frame/type variants) to render.
    public let configurations: [SnapshotConfiguration]
    /// Whether the content needs the async settle loop before capture.
    public let settle: SnapshotSettle
    /// The content rendered under each configuration.
    public let content: AnyView

    public var id: String {
        name
    }

    @MainActor
    public init(
        name: String,
        configurations: [SnapshotConfiguration],
        settle: SnapshotSettle = .settled,
        @ViewBuilder content: @MainActor () -> some View,
    ) {
        self.name = name
        self.configurations = configurations
        self.settle = settle
        self.content = AnyView(content())
    }

    /// The configurations that can render in a plain SwiftUI preview. Accessibility
    /// captures need the test-only library's VoiceOver parser, so they're dropped
    /// from the cutsheet (they still run as snapshot tests).
    public var previewConfigurations: [SnapshotConfiguration] {
        configurations.filter { $0.snapshotType != .accessibility }
    }
}

extension SnapshotCase: View {
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(previewConfigurations, id: \.self) { configuration in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(for: configuration))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    framed(for: configuration)
                        .snapshotTraits(configuration)
                        // Previews mirror what the tests capture, so each
                        // variant renders its deterministic capture state.
                        .environment(\.isCapturingSnapshot, true)
                }
            }
        }
    }

    private func label(for configuration: SnapshotConfiguration) -> String {
        configuration.identifier.isEmpty ? "default" : configuration.identifier
    }

    @ViewBuilder
    private func framed(for configuration: SnapshotConfiguration) -> some View {
        switch configuration.device.size {
            case let .intrinsic(maxWidth):
                if let maxWidth {
                    content.frame(maxWidth: maxWidth, alignment: .leading)
                } else {
                    content
                }
            case let .fixed(size):
                content.frame(width: size.width, height: size.height)
            case let .fullContent(width):
                // No height: in the cutsheet's scroll view the content gets an
                // unbounded proposal and takes its ideal (content) height, the
                // preview analogue of the pipeline's content measurement.
                content.frame(width: width)
        }
    }
}
