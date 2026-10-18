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
        case failed(any Error)
    }

    let webView: WKWebView
    private(set) var size: CGSize
    private let html: String
    private var loadState: LoadState = .loading
    private var paintContinuation: CheckedContinuation<Void, any Error>?

    private init(html: String, size: CGSize, configuration: WKWebViewConfiguration) {
        self.html = html
        self.size = size
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Capture the document itself, without native chrome blurring its edges.
        webView.scrollView.topEdgeEffect.isHidden = true
        webView.scrollView.bottomEdgeEffect.isHidden = true
        webView.scrollView.leftEdgeEffect.isHidden = true
        webView.scrollView.rightEdgeEffect.isHidden = true
    }

    static func make(
        _ html: String,
        configuration: SnapshotConfiguration,
    ) async throws -> SnapshotWebPage {
        try Task.checkCancellation()
        guard configuration.snapshotType == .standard,
              case let .fullContent(width, minimumHeight) = configuration.device.size
        else { throw Failure.requiresStandardFullContent }
        let size = CGSize(width: width, height: minimumHeight ?? 1)
        try validateSize(size, scale: 1)
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = false
        if configuration.uiTraitCollection.userInterfaceIdiom == .pad {
            webConfiguration.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "SnapshotKitTesting.offline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#,
        )
        guard let rules else { throw Failure.missingContentRules }
        try Task.checkCancellation()
        webConfiguration.userContentController.add(rules)
        return SnapshotWebPage(html: html, size: size, configuration: webConfiguration)
    }

    /// Runs once from the shared pre-measure hook, while this view is hosted.
    /// Its timeout includes navigation, fonts, and every viewport reflow pass.
    func prepare() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let minimumSize = size
            let scale = webView.traitCollection.displayScale
            try Self.validateSize(size, scale: scale)
            guard webView.loadHTMLString(html, baseURL: nil) != nil
            else { throw Failure.navigationDidNotStart }
            try await waitForLoad()
            // A viewport resize can change CSS layout. Await each paint before
            // remeasurement; never record the final arbitrary height on failure.
            for _ in 0 ..< 5 {
                try Task.checkCancellation()
                try await waitForPaint()
                let measured = CGSize(
                    width: minimumSize.width,
                    height: max(minimumSize.height, ceil(webView.scrollView.contentSize.height)),
                )
                try Self.validateSize(measured, scale: scale)
                if size == measured { return }
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
        webView.stopLoading()
        webView.navigationDelegate = nil
        loadState = .failed(CancellationError())
        // WebKit's async JavaScript overlay does not cancel a pending RAF.
        // Resume our waiter on cancellation; a later callback is harmless.
        let continuation = paintContinuation
        paintContinuation = nil
        continuation?.resume(throwing: CancellationError())
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
                case .loaded: return
                case let .failed(error): throw error
                case .loading: try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func waitForPaint() async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            paintContinuation = continuation
            webView.callAsyncJavaScript(
                """
                await document.fonts.ready;
                await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                """,
                arguments: [:],
                in: nil,
                in: .page,
            ) { [weak self] result in
                guard let self else { return }
                let pending = paintContinuation
                paintContinuation = nil
                pending?.resume(with: result.map { _ in () })
            }
        }
        try Task.checkCancellation()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loadState = .loaded
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        loadState = .failed(error)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: any Error,
    ) {
        loadState = .failed(error)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        loadState = .failed(WKError(.webContentProcessTerminated))
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
