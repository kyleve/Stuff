import SwiftUI
import ViewDocumentCore

/// Hosts prepared document or native artwork in paint bounds that never change the host's size.
public struct BArtworkLayer<SurfaceShape: InsettableShape, Content: View>: View {
    private let placement: BArtworkPlacement
    private let shape: SurfaceShape
    private let role: BSurfaceLayerRole
    private let maximumOutsets: ViewArtworkPlacement.Outsets?
    private let content: Content
    @Environment(\.bViewDocumentStylesheet) private var sheet
    /// Layout direction is local container geometry and can differ beneath the Broadway root.
    @Environment(\.layoutDirection) private var layoutDirection

    public init(
        placement: BArtworkPlacement,
        shape: SurfaceShape,
        role: BSurfaceLayerRole,
        maximumOutsets: ViewArtworkPlacement.Outsets? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        self.placement = placement
        self.shape = shape
        self.role = role
        self.maximumOutsets = maximumOutsets
        self.content = content()
    }

    public var body: some View {
        if sheet.shows(role) {
            GeometryReader { host in
                let geometry = placement.value.geometry(
                    in: .init(width: host.size.width, height: host.size.height),
                    rightToLeft: layoutDirection == .rightToLeft,
                    maximumOutsets: maximumOutsets,
                )
                let frame = geometry.frame
                let bounds = geometry.paintBounds
                if frame.width > 0, frame.height > 0 {
                    content
                        .frame(width: frame.width, height: frame.height)
                        .position(
                            x: frame.x + frame.width / 2 - bounds.x,
                            y: frame.y + frame.height / 2 - bounds.y,
                        )
                        .frame(width: bounds.width, height: bounds.height)
                        .mask {
                            BArtworkClip(
                                shape: shape,
                                host: host.size,
                                paintBounds: bounds,
                                plane: placement.value.plane,
                            )
                            .fill(style: FillStyle(eoFill: true))
                        }
                        .offset(x: bounds.x, y: bounds.y)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Foreground paint is restricted to a narrow edge band and the declared exterior bounds.
struct BArtworkClip<SurfaceShape: InsettableShape>: Shape {
    let shape: SurfaceShape
    let host: CGSize
    let paintBounds: ViewArtworkPlacement.Frame
    let plane: ViewArtworkPlacement.Plane

    func path(in rect: CGRect) -> Path {
        let surface = CGRect(
            x: -paintBounds.x,
            y: -paintBounds.y,
            width: host.width,
            height: host.height,
        )
        switch plane {
            case .interior: return shape.path(in: surface)
            case .exterior:
                // Keep a protected center even when a host is smaller than the ordinary edge band.
                let edge = min(16, min(host.width, host.height) / 4)
                var path = Path(rect)
                path.addPath(shape.inset(by: edge).path(in: surface))
                return path
        }
    }
}

#if DEBUG
    #Preview("Bounded exterior artwork") { BArtworkPreview.make() }

    @MainActor
    private enum BArtworkPreview {
        static func make() -> some View {
            do {
                let placement = try BArtworkPlacement(.init(
                    anchor: .bottomTrailing,
                    size: .fixed(width: 48, height: 48),
                    offset: .init(x: 8, y: 24),
                    plane: .exterior,
                    outsets: .init(top: 0, leading: 0, bottom: 24, trailing: 8),
                ))
                return Text("Native card").padding(40).background(
                    .orange.opacity(0.15),
                    in: .rect(cornerRadius: 20),
                )
                .overlay {
                    BArtworkLayer(
                        placement: placement,
                        shape: RoundedRectangle(cornerRadius: 20),
                        role: .ornament,
                    ) {
                        Circle().fill(.orange)
                    }
                }
                .padding(40).broadwayRoot()
            } catch {
                preconditionFailure("Invalid artwork preview: \(error)")
            }
        }
    }
#endif
