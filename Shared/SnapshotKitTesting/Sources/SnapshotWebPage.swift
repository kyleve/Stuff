import SnapshotKit
import SwiftUI
import WebKit

/// Prepares an offline document inside the regular snapshot host. WebKit owns
/// asynchronous page layout; the shared renderer owns hosting and pixel capture.
@MainActor
final class SnapshotWebPage: NSObject, WKNavigationDelegate {
    /// Seconds allowed for a cold WebKit process, navigation, fonts, and reflow.
    static let readinessTimeout: TimeInterval = 10

    enum Failure: Error {
        case requiresStandardFullContent
        case navigationDidNotStart
        case invalidContentSize
        case heightDidNotConverge
        case missingContentRules
    }

    private enum LoadState {
        case loading
        case loaded
        case ready
        case failed(any Error)
    }

    /// The DOM measurement owns sizing; UIKit's scroll mirror can lag behind it.
    final class DocumentView: WKWebView, SnapshotContentSizeProviding {}

    let webView: DocumentView
    var reusableWebView: DocumentView? {
        guard case .ready = loadState else { return nil }
        return webView
    }

    private(set) var size: CGSize
    private let initialSize: CGSize
    private let html: String
    private let contentMode: WKWebpagePreferences.ContentMode
    private let decodesImages: Bool
    private var navigation: WKNavigation?
    private var loadState: LoadState = .loading
    private var paintContinuation: CheckedContinuation<CGFloat, any Error>?

    private init(
        html: String,
        size: CGSize,
        webView: DocumentView,
        contentMode: WKWebpagePreferences.ContentMode,
        decodesImages: Bool,
    ) {
        self.html = html
        initialSize = size
        self.size = size
        self.webView = webView
        self.contentMode = contentMode
        self.decodesImages = decodesImages
        super.init()
        webView.frame = CGRect(origin: .zero, size: size)
        webView.navigationDelegate = self
    }

    static func make(
        _ html: String,
        configuration: SnapshotConfiguration,
        reusing previous: DocumentView? = nil,
        decodesImages: Bool = false,
    ) async throws -> SnapshotWebPage {
        try Task.checkCancellation()
        guard configuration.snapshotType == .standard,
              case let .fullContent(width, minimumHeight) = configuration.device.size
        else { throw Failure.requiresStandardFullContent }
        let size = CGSize(width: width, height: minimumHeight ?? 1)
        try validateSize(size, scale: 1)
        let webView: DocumentView
        if let previous {
            let dataStore = previous.configuration.websiteDataStore
            await dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast,
            )
            try Task.checkCancellation()
            webView = previous
        } else {
            webView = try await makeWebView(size: size)
        }
        return SnapshotWebPage(
            html: html,
            size: size,
            webView: webView,
            contentMode: configuration.uiTraitCollection
                .userInterfaceIdiom == .pad ? .desktop : .recommended,
            decodesImages: decodesImages,
        )
    }

    private static func makeWebView(size: CGSize) async throws -> DocumentView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = false
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "SnapshotKitTesting.offline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#,
        )
        guard let rules else { throw Failure.missingContentRules }
        try Task.checkCancellation()
        webConfiguration.userContentController.add(rules)
        let webView = DocumentView(
            frame: CGRect(origin: .zero, size: size),
            configuration: webConfiguration,
        )
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Capture the document itself, without native chrome blurring its edges.
        webView.scrollView.topEdgeEffect.isHidden = true
        webView.scrollView.bottomEdgeEffect.isHidden = true
        webView.scrollView.leftEdgeEffect.isHidden = true
        webView.scrollView.rightEdgeEffect.isHidden = true
        return webView
    }

    /// Runs from the shared pre-measure hook on each hosted capture attempt.
    /// Its timeout includes navigation, fonts, and every viewport reflow pass.
    func prepare() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            // A retry can start after the previous attempt grew to the full document height.
            loadState = .loading
            size = initialSize
            webView.frame.size = size
            webView.scrollView.setContentOffset(.zero, animated: false)
            let scale = webView.traitCollection.displayScale
            try Self.validateSize(size, scale: scale)
            navigation = webView.loadHTMLString(html, baseURL: nil)
            guard navigation != nil else { throw Failure.navigationDidNotStart }
            try await waitForLoad()
            // A viewport resize can change CSS layout. Await each paint before
            // remeasurement; never record the final arbitrary height on failure.
            // Read height in WebKit: UIScrollView contentSize can lag the painted DOM.
            for _ in 0 ..< 5 {
                try Task.checkCancellation()
                let documentHeight = try await waitForPaint()
                if case let .failed(error) = loadState {
                    throw error
                }
                let measured = CGSize(
                    width: initialSize.width,
                    height: max(initialSize.height, ceil(documentHeight)),
                )
                try Self.validateSize(measured, scale: scale)
                if size == measured {
                    loadState = .ready
                    return
                }
                size = measured
                webView.frame.size = measured
                webView.invalidateIntrinsicContentSize()
                webView.layoutIfNeeded()
            }
            throw Failure.heightDidNotConverge
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func stop() {
        // A cancelled hook can deliver its cleanup after the next wrapper took ownership.
        if webView.navigationDelegate === self {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }
        fail(CancellationError())
    }

    private func fail(_ error: any Error) {
        navigation = nil
        loadState = .failed(error)
        // WebKit's async JavaScript overlay does not cancel a pending RAF.
        // Resume our waiter on cancellation; a later callback is harmless.
        let continuation = paintContinuation
        paintContinuation = nil
        continuation?.resume(throwing: error)
    }

    private static func validateSize(_ size: CGSize, scale: CGFloat) throws {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixels.width.isFinite, pixels.height.isFinite,
              pixels.width > 0, pixels.height > 0,
              pixels.width <= 32000, pixels.height <= 32000,
              pixels.width * pixels.height <= 100_000_000
        else { throw Failure.invalidContentSize }
    }

    private func waitForLoad() async throws {
        while true {
            try Task.checkCancellation()
            switch loadState {
                case .loaded, .ready: return
                case let .failed(error): throw error
                case .loading: try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func waitForPaint() async throws -> CGFloat {
        try Task.checkCancellation()
        let height: CGFloat = try await withCheckedThrowingContinuation { continuation in
            paintContinuation = continuation
            webView.callAsyncJavaScript(
                """
                await document.fonts.ready;
                if (decodesImages) {
                    const selectedImages = Array.from(document.images).filter(image => image.currentSrc);
                    await Promise.all(selectedImages.map(image => image.decode()));
                }
                await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                return Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight ?? 0);
                """,
                arguments: ["decodesImages": decodesImages],
                in: nil,
                in: .page,
            ) { [weak self] result in
                guard let self else { return }
                let pending = paintContinuation
                paintContinuation = nil
                pending?.resume(with: result.flatMap { value in
                    guard let height = value as? NSNumber else {
                        return .failure(Failure.invalidContentSize)
                    }
                    return .success(CGFloat(height.doubleValue))
                })
            }
        }
        try Task.checkCancellation()
        return height
    }

    func webView(
        _: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences,
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if action.targetFrame?.isMainFrame == true {
            preferences.preferredContentMode = contentMode
        }
        return (.allow, preferences)
    }

    func webView(_: WKWebView, didFinish completed: WKNavigation!) {
        guard let completed, navigation === completed else { return }
        loadState = .loaded
    }

    func webView(_: WKWebView, didFail failed: WKNavigation!, withError error: any Error) {
        guard let failed, navigation === failed else { return }
        fail(error)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation failed: WKNavigation!,
        withError error: any Error,
    ) {
        guard let failed, navigation === failed else { return }
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        fail(WKError(.webContentProcessTerminated))
    }
}

/// Reports WebKit's prepared document size to the shared intrinsic measurement.
struct SnapshotWebPageView: UIViewRepresentable {
    let page: SnapshotWebPage

    func makeUIView(context _: Context) -> WKWebView {
        page.webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    func sizeThatFits(_: ProposedViewSize, uiView _: WKWebView, context _: Context) -> CGSize? {
        page.size
    }
}
