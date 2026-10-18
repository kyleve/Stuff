import TestHostSupport
import UIKit
import WebKit

/// Hosts one offline page until navigation, fonts, layout, and WebKit painting finish.
/// Call only while holding SnapshotCaptureLock; the host window is shared.
@MainActor
final class SnapshotWebPage: UIViewController, WKNavigationDelegate {
    enum Failure: Error {
        case requiresStandardFullContent
        case loadTimedOut
        case navigationDidNotStart
        case invalidContentSize
        case heightDidNotConverge
        case missingImage
        case missingContentRules
    }

    private enum LoadState {
        case loading
        case loaded
        case failed(any Error)
    }

    private let webView: WKWebView
    private var loadState: LoadState = .loading

    private init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Capture the document itself, without native chrome blurring its edges.
        webView.scrollView.topEdgeEffect.isHidden = true
        webView.scrollView.bottomEdgeEffect.isHidden = true
        webView.scrollView.leftEdgeEffect.isHidden = true
        webView.scrollView.rightEdgeEffect.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = webView
    }

    static func capture(
        _ html: String,
        width: CGFloat,
        minimumHeight: CGFloat,
        traits: UITraitCollection,
    ) async throws -> UIImage {
        try validateSize(CGSize(width: width, height: minimumHeight), scale: 1)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // Match iPad's desktop page preference for an explicit tablet matrix.
        if traits.userInterfaceIdiom == .pad {
            configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "SnapshotKitTesting.offline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#,
        )
        guard let rules else { throw Failure.missingContentRules }
        configuration.userContentController.add(rules)
        let page = SnapshotWebPage(configuration: configuration)
        page.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
        page.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        page.traitOverrides.accessibilityContrast = traits.accessibilityContrast
        page.traitOverrides.layoutDirection = traits.layoutDirection
        page.traitOverrides.legibilityWeight = traits.legibilityWeight
        if traits.userInterfaceIdiom != .unspecified {
            page.traitOverrides.userInterfaceIdiom = traits.userInterfaceIdiom
            page.traitOverrides.horizontalSizeClass = traits.horizontalSizeClass
            page.traitOverrides.verticalSizeClass = traits.verticalSizeClass
        }
        var image: UIImage?
        try await TestHostSupport.show(page) { page in
            defer {
                page.webView.stopLoading()
                page.webView.navigationDelegate = nil
            }
            let scale = page.traitCollection.displayScale
            let initialSize = CGSize(width: width, height: minimumHeight)
            try validateSize(initialSize, scale: scale)
            page.view.frame = CGRect(origin: .zero, size: initialSize)
            guard page.webView.loadHTMLString(html, baseURL: nil) != nil
            else { throw Failure.navigationDidNotStart }
            try await page.waitForLoad()
            // Resizing the viewport can reflow the page. Require convergence;
            // never record the last arbitrary height after exhausting the bound.
            for _ in 0 ..< 5 {
                try Task.checkCancellation()
                try await page.waitForPaint()
                let height = max(minimumHeight, ceil(page.webView.scrollView.contentSize.height))
                let size = CGSize(width: width, height: height)
                try validateSize(size, scale: scale)
                if page.view.frame.size == size {
                    let snapshot = WKSnapshotConfiguration()
                    snapshot.rect = CGRect(origin: .zero, size: size)
                    snapshot.afterScreenUpdates = true
                    image = try await page.webView.takeSnapshot(configuration: snapshot)
                    try Task.checkCancellation()
                    return
                }
                page.view.frame.size = size
                page.view.layoutIfNeeded()
            }
            throw Failure.heightDidNotConverge
        }
        guard let image else { throw Failure.missingImage }
        return image
    }

    private static func validateSize(_ size: CGSize, scale: CGFloat) throws {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        // Bound WebKit's allocation before asking it to render a full document.
        guard pixels.width.isFinite, pixels.height.isFinite,
              pixels.width > 0, pixels.height > 0,
              pixels.width <= 32000, pixels.height <= 32000,
              pixels.width * pixels.height <= 100_000_000
        else { throw Failure.invalidContentSize }
    }

    private func waitForLoad() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while true {
            try Task.checkCancellation()
            switch loadState {
                case .loaded: return
                case let .failed(error): throw error
                case .loading:
                    guard ContinuousClock.now < deadline else { throw Failure.loadTimedOut }
                    try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func waitForPaint() async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            await document.fonts.ready;
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page,
        )
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
