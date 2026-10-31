@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct SnapshotImageRenderingTests {
    @Test func fixedViewportPreservesNativeTitleSpace() async throws {
        let host = UIHostingController(rootView: NavigationStack {
            Color.white
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Overview", systemImage: "square.grid.3x3", action: {})
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Planning", systemImage: "calendar.badge.clock", action: {})
                    }
                }
        })
        SnapshotConfiguration(device: .iPhone).applyTraits(to: host)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        _ = try await renderSnapshotImage(
            of: host,
            named: "native-title-space",
            safeAreaInsets: .zero,
            onReadyToSnapshot: {
                Self.expectUntruncatedTitle(in: host.view)
            },
        )
    }

    private static func expectUntruncatedTitle(in view: UIView) {
        func labels(in view: UIView) -> [UILabel] {
            (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
        }
        let titles = labels(in: view).filter { $0.text == "Calendar" }
        #expect(!titles.isEmpty)
        for title in titles {
            #expect(title.bounds.width >= title.intrinsicContentSize.width - 1)
        }
    }

    @Test func fixedViewportSettlementPreservesNativeBarGeometry() async throws {
        let configuration = SnapshotConfiguration(device: .duoInnerPortrait)
        let probe = NativeBarGeometryProbe()
        let host = UIHostingController(rootView: NativeBarGeometryFixture(probe: probe)
            .snapshotTraits(configuration))
        configuration.applyTraits(to: host)
        guard case let .fixed(size) = configuration.device.size else {
            Issue.record("The Duo viewport must use fixed sizing")
            return
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        _ = try await renderSnapshotImage(
            of: host,
            named: "native-bar-geometry",
            safeAreaInsets: configuration.device.safeAreaInsets.uiEdgeInsets,
            settle: .settledAtLeast(minDuration: 1.5),
            onReadyToSnapshot: {
                probe.begin()
                let outcome = await settleContent(host.view, named: "native-bar-geometry-proof")
                probe.end()
                #expect(outcome == .settled)
                #expect(!probe.measurements.isEmpty)
                #expect(probe.measurements.allSatisfy { $0 == probe.measurements.first })
                Self.expectUntruncatedTitle(in: host.view)
            },
        )
    }

    @Test(
        arguments: [UIEdgeInsets.zero, UIEdgeInsets(top: 5, left: 7, bottom: 9, right: 11)],
        Attachment.allCases,
    )
    func fixedViewportPropagatesInsetsToNativeChildren(
        requestedInsets: UIEdgeInsets,
        attachment: Attachment,
    ) async throws {
        for horizontalSizeClass in [UIUserInterfaceSizeClass.compact, .regular] {
            try waitFor { hostKeyWindow() != nil }
            let window = try #require(hostKeyWindow())
            let root = try #require(window.rootViewController)
            let host = UIViewController()
            host.traitOverrides.userInterfaceIdiom = .phone
            host.traitOverrides.horizontalSizeClass = horizontalSizeClass
            host.traitOverrides.verticalSizeClass = .regular
            let originalFrame = CGRect(origin: CGPoint(x: 13, y: 17), size: window.bounds.size)
            host.view.frame = originalFrame
            let child = UIViewController()
            host.addChild(child)
            child.view.frame = host.view.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.addSubview(child.view)
            child.didMove(toParent: host)
            switch attachment {
                case .none: break
                case .controller:
                    root.addChild(host)
                    root.view.addSubview(host.view)
                    host.didMove(toParent: root)
                case .view:
                    root.view.addSubview(host.view)
            }
            root.view.layoutIfNeeded()
            _ = try await renderSnapshotImage(
                of: host,
                named: "native-child-insets",
                safeAreaInsets: requestedInsets,
                settle: .settled,
                onReadyToSnapshot: {
                    #expect(child.view.safeAreaInsets == requestedInsets)
                },
            )
            #expect(host.view.frame == originalFrame)
            #expect(host.parent == nil)
            #expect(host.view.superview == nil)
        }
    }

    enum Attachment: CaseIterable {
        case none, controller, view
    }

    @Test func aNilInsetOverrideKeepsTheNativeScene() async throws {
        try waitFor { hostKeyWindow() != nil }
        let window = try #require(hostKeyWindow())
        let scene = try #require(window.windowScene)
        let host = UIHostingController(rootView: Color.red)
        host.view.frame = window.bounds
        _ = try await renderSnapshotImage(
            of: host,
            named: "native-scene",
            safeAreaInsets: nil,
            settle: .immediate,
            onReadyToSnapshot: {
                #expect(window.windowScene === scene)
                #expect(hostKeyWindow() === window)
                #expect(host.view.window === window)
            },
        )
        #expect(host.parent == nil)
        #expect(hostKeyWindow() === window)
    }

    @Test(arguments: [false, true], [false, true])
    func restoresTheMarkedWindowAfterCapture(fails: Bool, anotherWindowIsKey: Bool) async throws {
        for layout in CaptureLayout.allCases {
            try await verifyWindowRestoration(
                fails: fails,
                anotherWindowIsKey: anotherWindowIsKey,
                layout: layout,
            )
        }
    }

    private enum CaptureLayout: CaseIterable {
        case compactViewport, regularViewport, fullContent
    }

    private func verifyWindowRestoration(
        fails: Bool,
        anotherWindowIsKey: Bool,
        layout: CaptureLayout,
    ) async throws {
        let intrinsic = layout == .fullContent
        try waitFor { hostKeyWindow() != nil }
        let window = try #require(hostKeyWindow())
        let scene = try #require(window.windowScene)
        let otherWindow = UIWindow(windowScene: scene)
        defer {
            otherWindow.isHidden = true
            otherWindow.windowScene = nil
            window.makeKeyAndVisible()
        }
        if anotherWindowIsKey {
            otherWindow.rootViewController = UIViewController()
            otherWindow.makeKeyAndVisible()
            #expect(otherWindow.isKeyWindow)
            #expect(!window.isKeyWindow)
        }
        let root = try #require(window.rootViewController)
        let frame = window.frame
        let rootFrame = root.view.frame
        let rootInsets = root.additionalSafeAreaInsets
        let wasKey = window.isKeyWindow
        let wasHidden = window.isHidden
        let animationsWereEnabled = UIView.areAnimationsEnabled
        let host = UIHostingController(rootView: Color.red)
        host.traitOverrides.userInterfaceIdiom = .phone
        host.traitOverrides.horizontalSizeClass = layout == .regularViewport ? .regular : .compact
        host.traitOverrides.verticalSizeClass = .regular
        let additionalInsets = UIEdgeInsets(top: 5, left: 7, bottom: 9, right: 11)
        host.additionalSafeAreaInsets = additionalInsets
        let contentFrame = CGRect(x: 0, y: 0, width: 280, height: 400)
        host.view.frame = contentFrame
        let readiness: (@MainActor @Sendable () async throws -> Void)? = if fails {
            { throw WindowRestorationFailure.readiness }
        } else { nil }

        do {
            _ = try await renderSnapshotImage(
                of: host,
                named: "window-restoration",
                sizing: intrinsic ? .intrinsic(width: 280, minimumHeight: 400) : .fixed,
                onReadyToMeasure: readiness,
                settle: .immediate,
                onReadyToSnapshot: {
                    if layout == .regularViewport { #expect(window.windowScene === scene) }
                    else { #expect(window.windowScene == nil) }
                    #expect(host.view.window === window)
                    #expect(window.bounds.size == contentFrame.size)
                },
            )
            #expect(!fails)
        } catch {
            #expect(fails)
            if intrinsic {
                #expect(error as? WindowRestorationFailure == .readiness)
            } else {
                #expect(error as? SnapshotRenderingError == .measurementHookRequiresIntrinsicSizing(
                    name: "window-restoration",
                ))
            }
        }

        #expect(hostKeyWindow() === window)
        #expect(window.windowScene === scene)
        #expect(window.rootViewController === root)
        #expect(window.frame == frame)
        #expect(root.view.frame == rootFrame)
        #expect(root.additionalSafeAreaInsets == rootInsets)
        #expect(window.isKeyWindow == wasKey)
        if anotherWindowIsKey { #expect(otherWindow.isKeyWindow) }
        #expect(window.isHidden == wasHidden)
        #expect(UIView.areAnimationsEnabled == animationsWereEnabled)
        #expect(host.view.frame == contentFrame)
        #expect(host.additionalSafeAreaInsets == additionalInsets)
        #expect(host.parent == nil)
        #expect(root.children.isEmpty)
    }
}

@MainActor
private final class NativeBarGeometryProbe {
    struct Measurement: Equatable {
        let size: CGSize
        let topInset: CGFloat
        let bottomInset: CGFloat
    }

    private var latest: Measurement?
    private var isRecording = false
    private(set) var measurements: [Measurement] = []

    func record(_ measurement: Measurement) {
        guard measurement.size.width > 0, measurement.size.height > 0 else { return }
        latest = measurement
        if isRecording { measurements.append(measurement) }
    }

    func begin() {
        measurements = latest.map { [$0] } ?? []
        isRecording = true
    }

    func end() {
        isRecording = false
    }
}

private struct NativeBarGeometryFixture: View {
    let probe: NativeBarGeometryProbe
    @State private var position = ScrollPosition(idType: Int.self)

    var body: some View {
        TabView {
            Tab("History", systemImage: "calendar") {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    Text("Controls")
                        .navigationSplitViewColumnWidth(min: 280, ideal: 280)
                } detail: {
                    NavigationStack {
                        ScrollView {
                            VStack {
                                ForEach(0 ..< 12, id: \.self) { month in
                                    Text("Month \(month)")
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 240)
                                        .background(.blue.opacity(0.2))
                                        .id(month)
                                }
                            }
                            .scrollTargetLayout()
                            .padding()
                        }
                        .scrollPosition($position)
                        .task { position.scrollTo(id: 11, anchor: .bottom) }
                        .onScrollGeometryChange(for: NativeBarGeometryProbe.Measurement.self) {
                            .init(
                                size: $0.containerSize,
                                topInset: $0.contentInsets.top,
                                bottomInset: $0.contentInsets.bottom,
                            )
                        } action: { _, measurement in
                            probe.record(measurement)
                        }
                        .navigationTitle("Calendar")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Overview", systemImage: "square.grid.3x3", action: {})
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Planning", systemImage: "calendar.badge.clock", action: {})
                            }
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }
            Tab("Other", systemImage: "gear") { Color.gray }
        }
        .tabBarMinimizeBehavior(.never)
    }
}

private enum WindowRestorationFailure: Error, Equatable {
    case readiness
}
