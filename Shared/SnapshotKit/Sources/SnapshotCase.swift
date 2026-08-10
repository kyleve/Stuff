import SwiftUI

/// How a snapshot case's content reaches its capture-ready state.
public enum SnapshotSettle: Equatable, Sendable {
    /// Wait for the rendered content to quiesce before capture, so `.task`-driven
    /// async loads resolve first. The safe default.
    case settled
    /// ``settled`` with a raised minimum settle window. For content whose async
    /// appearance work starts *quiet* and lands after the default floor — the
    /// iOS 26 glass toolbar/tab bar adapts its material to the content behind it
    /// a few hundred ms after hosting, which no pixel-stability check can
    /// anticipate before it starts. The floor is paid on every capture of the
    /// case, so reserve it for cases that host such chrome.
    case settledAtLeast(minDuration: TimeInterval)
    /// The content is fully renderable after a layout pass: skip the settle loop.
    /// A single task yield still runs, so a `.task` body that merely sets state
    /// synchronously gets one shot — but nothing that needs real time will load.
    case immediate
}

/// When intrinsic/full-content sizing may measure a snapshot case.
public enum SnapshotMeasurementReadiness: Equatable, Sendable {
    /// Use the final capture's settle policy before measuring. The safe default
    /// for content whose loaded state can change its ideal height.
    case sameAsCapture
    /// Measure after one task yield and layout pass, while leaving the final
    /// capture's settle policy unchanged. Use for synchronously sized fixtures
    /// whose visual state may still need time to settle before capture.
    case immediate
    /// Wait for ordinary quiescence before measuring, independently of a raised
    /// minimum window used by the final capture.
    case settled
}

/// A named group of snapshot variants for a component: the configurations to
/// render, and the content to render under each.
///
/// It is also a `View`, so it renders a labeled, scrollable cutsheet of its
/// variants inside a `#Preview` — the same matrix, traits, and content the
/// snapshot tests capture. Test-only capture mechanics are documented on
/// ``previewConfigurations``.
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
    /// When intrinsic/full-content sizing may measure the content.
    public let measurementReadiness: SnapshotMeasurementReadiness
    /// Runs in the capture pipeline after the content has settled and before
    /// the image is taken — the deterministic point to focus a field or trigger
    /// a presented state. Its effects are settled again before capture. `nil`
    /// for content that renders as declared; the preview cutsheet ignores it
    /// (only the test pipeline can re-settle around it).
    public let onReadyToSnapshot: (@MainActor () async -> Void)?
    /// The content rendered under each configuration.
    ///
    /// The builder stays lazy so describing a snapshot matrix does not also
    /// instantiate every view and its model. Each access creates an independent
    /// view value for its configuration.
    @MainActor public var content: AnyView {
        contentFactory()
    }

    private let contentFactory: @MainActor () -> AnyView

    public var id: String {
        name
    }

    @MainActor
    public init(
        name: String,
        configurations: [SnapshotConfiguration],
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        settle: SnapshotSettle = .settled,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) {
        self.name = name
        self.configurations = configurations
        self.measurementReadiness = measurementReadiness
        self.settle = settle
        self.onReadyToSnapshot = onReadyToSnapshot
        contentFactory = { AnyView(content()) }
    }

    /// The configurations that can render in a plain SwiftUI preview. Accessibility
    /// captures need the test-only library's VoiceOver parser, so they're dropped
    /// from the cutsheet (they still run as snapshot tests). The cutsheet also
    /// cannot perform the capture pipeline's UIKit-backed `List`/`Form`
    /// measurement, safe-area override, async ready hook, or tile-and-stitch;
    /// full-content preview height is therefore an approximation while the test
    /// capture is authoritative.
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
                        // Preview the same deterministic content state as tests;
                        // capture-only mechanics remain test-pipeline concerns.
                        .environment(\.isCapturingSnapshot, true)
                }
            }
        }
    }

    private func label(for configuration: SnapshotConfiguration) -> String {
        configuration.identifier.isEmpty ? "default" : configuration.identifier
    }

    @ViewBuilder
    @MainActor private func framed(for configuration: SnapshotConfiguration) -> some View {
        switch configuration.device.size {
            case let .intrinsic(maxWidth):
                if let maxWidth {
                    content.frame(maxWidth: maxWidth, alignment: .leading)
                } else {
                    content
                }
            case let .fixed(size):
                content.frame(width: size.width, height: size.height)
            case let .fullContent(width, minimumHeight):
                // The cutsheet shares the viewport minimum but cannot run the
                // test pipeline's UIKit descendant measurement.
                content
                    .frame(width: width)
                    .frame(minHeight: minimumHeight)
        }
    }
}
