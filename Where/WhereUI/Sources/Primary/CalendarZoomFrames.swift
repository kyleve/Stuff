import SwiftUI

struct CalendarZoomFrames: PreferenceKey {
    typealias Mode = CalendarPresentationState.Mode
    typealias Target = CalendarPresentationState.Target
    enum Frame: Hashable {
        case content
        case tile(Target)
    }

    static let defaultValue: [Mode: [Frame: Anchor<CGRect>]] = [:]

    static func measure(
        _ anchors: [Frame: Anchor<CGRect>],
        in proxy: GeometryProxy,
        mode: Mode,
        scrollOffset: CGPoint,
    ) -> CalendarZoomTransitionState.Measurement? {
        guard let content = anchors[.content] else { return nil }
        let contentFrame = proxy[content]
        // Resolve anchors relative to their content, then apply the current scroll
        // offset. Anchors alone do not update as the viewport scrolls.
        let translation = CGPoint(
            x: -contentFrame.minX - scrollOffset.x,
            y: -contentFrame.minY - scrollOffset.y,
        )
        let frames = anchors.reduce(into: [Target: CGRect]()) { frames, entry in
            switch entry.key {
                case .content: break
                case let .tile(target):
                    frames[target] = proxy[entry.value].offsetBy(
                        dx: translation.x,
                        dy: translation.y,
                    )
            }
        }
        return .init(
            mode: mode,
            frames: frames,
            viewport: CGRect(origin: .zero, size: proxy.size),
            content: contentFrame.offsetBy(dx: translation.x, dy: translation.y),
        )
    }

    static func reduce(
        value: inout [Mode: [Frame: Anchor<CGRect>]],
        nextValue: () -> [Mode: [Frame: Anchor<CGRect>]],
    ) {
        for (mode, frames) in nextValue() {
            value[mode, default: [:]].merge(frames, uniquingKeysWith: { _, new in new })
        }
    }
}
