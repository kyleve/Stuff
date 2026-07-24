#if canImport(UIKit)
    import Foundation
    import PortholeCore
    import UIKit

    /// The built-in `ui` connector (iOS only): inspect the window/view hierarchy
    /// and accessibility tree, capture a screenshot, and open a URL in the app.
    /// Auto-registered by ``Porthole`` on iOS.
    public final class ViewTreeConnector: PortholeConnector {
        public let descriptor = PortholeConnectorDescriptor(
            id: "ui",
            title: "UI",
            summary: "Inspect the app's window and view hierarchy, its accessibility tree, take a screenshot, or open a URL.",
            version: 1,
        )

        public init() {}

        public func actions() -> [PortholeAction] {
            [
                PortholeAction(
                    descriptor: PortholeActionDescriptor(
                        id: "screenshot",
                        title: "Screenshot",
                        summary: "Render a window to a PNG image so you can see the current screen.",
                        parameters: .object(["windowIndex": .integer("Which window (default 0)")]),
                        isDestructive: false,
                    ),
                    handler: { parameters in
                        let index = Int(parameters["windowIndex"]?.intValue ?? 0)
                        return try await MainActor.run { try Self.screenshot(windowIndex: index) }
                    },
                ),
                PortholeAction(
                    descriptor: PortholeActionDescriptor(
                        id: "open-url",
                        title: "Open URL",
                        summary: "Open a URL in the app — deep links, universal links, and custom schemes all navigate the app.",
                        parameters: .object(["url": .string("The URL to open")], required: ["url"]),
                        isDestructive: false,
                    ),
                    handler: { parameters in
                        guard let string = parameters["url"]?.stringValue,
                              let url = URL(string: string)
                        else {
                            throw PortholeError.invalidParameters("`url` is not a valid URL")
                        }
                        return await .object(["opened": .bool(Self.openURL(url))])
                    },
                ),
            ]
        }

        public func dataSources() -> [PortholeDataSource] {
            [
                PortholeDataSource(
                    descriptor: PortholeDataSourceDescriptor(
                        id: "windows",
                        title: "Windows",
                        summary: "One row per on-screen window.",
                        rowSchema: .object([
                            "index": .integer(),
                            "class": .string(),
                            "isKeyWindow": .boolean(),
                        ]),
                        filters: .object([:]),
                        supportsSubscription: false,
                    ),
                    fetch: { _ in await MainActor.run { Self.windowsPage() } },
                ),
                PortholeDataSource(
                    descriptor: PortholeDataSourceDescriptor(
                        id: "view-tree",
                        title: "View tree",
                        summary: "The recursive view hierarchy of a window as a single nested row.",
                        rowSchema: .object([
                            "class": .string(),
                            "children": .array(of: .object([:])),
                        ]),
                        filters: .object([
                            "windowIndex": .integer("Which window (default 0)"),
                            "maxDepth": .integer("Maximum depth (default 50)"),
                        ]),
                        supportsSubscription: false,
                    ),
                    fetch: { query in
                        let windowIndex = Int(query.filters["windowIndex"]?.intValue ?? 0)
                        let maxDepth = Int(query.filters["maxDepth"]?.intValue ?? 50)
                        return await MainActor.run { Self.viewTreePage(
                            windowIndex: windowIndex,
                            maxDepth: maxDepth,
                        ) }
                    },
                ),
                PortholeDataSource(
                    descriptor: PortholeDataSourceDescriptor(
                        id: "accessibility-tree",
                        title: "Accessibility tree",
                        summary: "The accessibility element hierarchy of a window as a single nested row.",
                        rowSchema: .object([
                            "label": .string(),
                            "children": .array(of: .object([:])),
                        ]),
                        filters: .object(["windowIndex": .integer("Which window (default 0)")]),
                        supportsSubscription: false,
                    ),
                    fetch: { query in
                        let windowIndex = Int(query.filters["windowIndex"]?.intValue ?? 0)
                        return await MainActor
                            .run { Self.accessibilityTreePage(windowIndex: windowIndex) }
                    },
                ),
            ]
        }

        // MARK: - Capture (main actor)

        @MainActor private static func openURL(_ url: URL) async -> Bool {
            await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
        }

        @MainActor private static func windows() -> [UIWindow] {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
        }

        @MainActor private static func window(at index: Int) -> UIWindow? {
            let all = windows()
            return all.indices.contains(index) ? all[index] : nil
        }

        @MainActor private static func windowsPage() -> PortholePage {
            let rows = windows().enumerated().map { index, window in
                PortholeValue.object([
                    "index": .int(Int64(index)),
                    "class": .string(String(describing: type(of: window))),
                    "frame": frame(window.frame),
                    "isKeyWindow": .bool(window.isKeyWindow),
                ])
            }
            return PortholePage(rows: rows, totalCount: rows.count)
        }

        @MainActor private static func viewTreePage(
            windowIndex: Int,
            maxDepth: Int,
        ) -> PortholePage {
            guard let window = window(at: windowIndex) else { return PortholePage(rows: []) }
            return PortholePage(
                rows: [viewNode(window, depth: 0, maxDepth: maxDepth)],
                totalCount: 1,
            )
        }

        @MainActor private static func viewNode(
            _ view: UIView,
            depth: Int,
            maxDepth: Int,
        ) -> PortholeValue {
            var object: [String: PortholeValue] = [
                "class": .string(String(describing: type(of: view))),
                "frame": frame(view.frame),
                "isHidden": .bool(view.isHidden),
                "alpha": .double(Double(view.alpha)),
            ]
            if let id = view
                .accessibilityIdentifier { object["accessibilityIdentifier"] = .string(id) }
            if let label = view.accessibilityLabel { object["accessibilityLabel"] = .string(label) }
            if depth < maxDepth, !view.subviews.isEmpty {
                object["children"] = .array(view.subviews.map { viewNode(
                    $0,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                ) })
            }
            return .object(object)
        }

        @MainActor private static func accessibilityTreePage(windowIndex: Int) -> PortholePage {
            guard let window = window(at: windowIndex) else { return PortholePage(rows: []) }
            return PortholePage(rows: [accessibilityNode(window)], totalCount: 1)
        }

        @MainActor private static func accessibilityNode(_ object: NSObject) -> PortholeValue {
            var node: [String: PortholeValue] = [
                "class": .string(String(describing: type(of: object))),
            ]
            if let element = object as? UIAccessibilityIdentification,
               let id = element.accessibilityIdentifier
            {
                node["accessibilityIdentifier"] = .string(id)
            }
            if object.isAccessibilityElement {
                if let label = object.accessibilityLabel { node["label"] = .string(label) }
                if let value = object.accessibilityValue { node["value"] = .string(value) }
                node["isAccessibilityElement"] = .bool(true)
            }
            let children = object.accessibilityElements as? [NSObject]
                ?? (object as? UIView)?.subviews ?? []
            if !children.isEmpty {
                node["children"] = .array(children.map(accessibilityNode))
            }
            return .object(node)
        }

        @MainActor private static func screenshot(windowIndex: Int) throws -> PortholeValue {
            guard let window = window(at: windowIndex) else {
                throw PortholeError.invalidParameters("No window at index \(windowIndex)")
            }
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard let png = image.pngData() else {
                throw PortholeError.handlerFailed("Failed to render PNG")
            }
            return .object([
                "image": .data(png),
                "width": .int(Int64(image.size.width * image.scale)),
                "height": .int(Int64(image.size.height * image.scale)),
                "scale": .double(Double(image.scale)),
            ])
        }

        private static func frame(_ rect: CGRect) -> PortholeValue {
            .object([
                "x": .double(Double(rect.origin.x)),
                "y": .double(Double(rect.origin.y)),
                "width": .double(Double(rect.width)),
                "height": .double(Double(rect.height)),
            ])
        }
    }
#endif
