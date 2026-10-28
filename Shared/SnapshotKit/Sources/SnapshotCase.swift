import SwiftUI

/// How a snapshot case's content reaches its capture-ready state.
public enum SnapshotSettle: Equatable, Sendable {
    /// Wait for the rendered content to quiesce before capture, so `.task`-driven
    /// async loads resolve first. The safe default.
    case settled
    /// ``settled`` with a raised minimum settle window. For content whose async
    /// appearance work starts *quiet* and lands after the default floor — the
    /// native glass toolbar/tab bar adapts its material to the content behind it
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
/// Accessibility variants are excluded from that preview because their
/// annotation renderer is test-only (see ``previewConfigurations``).
public struct SnapshotCase: Identifiable {
    /// The case name — groups a component's variants and prefixes their
    /// reference-image identifiers.
    public let name: String
    public let referenceGroup: SnapshotReferenceGroup?
    /// The configurations (appearance/frame/type variants) to render.
    public let configurations: [SnapshotConfiguration]
    /// Whether the content needs the async settle loop before capture.
    public let settle: SnapshotSettle
    /// When intrinsic/full-content sizing may measure the content.
    public let measurementReadiness: SnapshotMeasurementReadiness
    /// Runs after intrinsic/full-content content is hosted and laid out, but
    /// before it settles and is measured. Use it to await a deterministic
    /// content-ready signal when the loaded state changes ideal height. `nil`
    /// for synchronously measurable content; fixed-size configurations reject
    /// a hook because they do not have a measurement phase.
    public let onReadyToMeasure: (@MainActor () async -> Void)?
    /// Runs in the capture pipeline after the content has settled and before
    /// the image is taken — the deterministic point to focus a field or trigger
    /// a presented state. Its effects are settled again before capture. `nil`
    /// for content that renders as declared; the preview cutsheet ignores it
    /// (only the test pipeline can re-settle around it).
    public let onReadyToSnapshot: (@MainActor () async -> Void)?
    /// Capture machinery is shared with SnapshotKitTesting and Flyover. Author cases through
    /// the single-view initializer or the validated cutsheet builder.
    @_spi(Capture) public enum Capture {
        case single(@MainActor () -> AnyView)
        case cutsheet(SnapshotPanelCollection)
    }

    @_spi(Capture) public let capture: Capture

    var isCutsheet: Bool {
        switch capture {
            case .single: false
            case .cutsheet: true
        }
    }

    /// Structured preview identity keeps a group distinct from punctuation in a case name.
    public struct ID: Hashable, Sendable {
        public let referenceGroup: SnapshotReferenceGroup?
        public let name: String
    }

    public var id: ID {
        ID(referenceGroup: referenceGroup, name: name)
    }

    @MainActor
    public init(
        name: String,
        configurations: [SnapshotConfiguration],
        referenceGroup: SnapshotReferenceGroup? = nil,
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        onReadyToMeasure: (@MainActor () async -> Void)? = nil,
        settle: SnapshotSettle = .settled,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) {
        self.name = name
        self.referenceGroup = referenceGroup
        self.configurations = configurations
        self.measurementReadiness = measurementReadiness
        self.onReadyToMeasure = onReadyToMeasure
        self.settle = settle
        self.onReadyToSnapshot = onReadyToSnapshot
        capture = .single { AnyView(content()) }
    }

    @MainActor
    init(
        name: String,
        configurations: [SnapshotConfiguration],
        referenceGroup: SnapshotReferenceGroup?,
        measurementReadiness: SnapshotMeasurementReadiness,
        onReadyToMeasure: (@MainActor () async -> Void)?,
        settle: SnapshotSettle,
        onReadyToSnapshot: (@MainActor () async -> Void)?,
        panels: SnapshotPanelCollection,
    ) {
        self.name = name
        self.configurations = configurations
        self.referenceGroup = referenceGroup
        self.measurementReadiness = measurementReadiness
        self.onReadyToMeasure = onReadyToMeasure
        self.settle = settle
        self.onReadyToSnapshot = onReadyToSnapshot
        capture = .cutsheet(panels)
    }

    /// The configurations that can render without linking test-only dependencies.
    /// Accessibility annotations belong to `SnapshotKitTesting`, so those variants
    /// are dropped from the cutsheet (they still run as snapshot tests). The cutsheet also
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
                    switch capture {
                        case let .single(content):
                            framed(content(), for: configuration)
                                .snapshotTraits(configuration)
                                .environment(\.isCapturingSnapshot, true)
                        case let .cutsheet(panels):
                            let width = configuration.device.size.previewPanelWidth
                            LazyVGrid(
                                columns: [GridItem(.fixed(width)), GridItem(.fixed(width))],
                                spacing: 16,
                            ) {
                                ForEach(panels.panels) { panel in
                                    VStack(alignment: .leading) {
                                        Text(panel.label).font(.caption)
                                        framed(panel.content, for: configuration)
                                            .snapshotTraits(configuration)
                                            .environment(\.isCapturingSnapshot, true)
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    private func label(for configuration: SnapshotConfiguration) -> String {
        configuration.identifier.isEmpty ? "default" : configuration.identifier
    }

    @ViewBuilder
    @MainActor private func framed(
        _ content: AnyView,
        for configuration: SnapshotConfiguration,
    ) -> some View {
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
            case let .fullContent2D(minimumSize):
                // Two-axis expansion is capture-only; preview the declared
                // minimum viewport rather than an unbounded canvas.
                content.frame(width: minimumSize.width, height: minimumSize.height)
        }
    }
}

extension SnapshotConfiguration.SizeStrategy {
    fileprivate var previewPanelWidth: CGFloat {
        switch self {
            case let .fixed(size): size.width
            case let .intrinsic(maxWidth): maxWidth ?? 402
            case let .fullContent(width, _): width
            case let .fullContent2D(minimumSize): minimumSize.width
        }
    }
}
