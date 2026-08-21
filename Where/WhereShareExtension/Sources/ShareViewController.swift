import PeriscopeCore
import SwiftUI
import UIKit
import WhereCore

/// Principal class for the Where share extension (see `Info.plist`'s
/// `NSExtensionPrincipalClass`). Hosts the SwiftUI `ShareEvidenceView` in a
/// `UIHostingController` and bridges its save/cancel actions to the extension
/// request lifecycle.
final class ShareViewController: UIViewController {
    private static let logger = WhereLog.root(ShareExtensionLog.self)

    /// The embedded SwiftUI host, re-framed to fill our bounds each layout pass.
    private var host: UIHostingController<ShareEvidenceView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Self.logger { .opened(itemCount: items.count) }

        let buildEnvironment = WhereShareBuildEnvironment.current()
        let model = ShareEvidenceModel(
            items: items,
            storage: .localOnly(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            ),
        )
        let root = ShareEvidenceView(
            model: model,
            onSave: { [weak self] in self?.complete() },
            onCancel: { [weak self] in self?.cancel() },
        )
        embed(UIHostingController(rootView: root))
    }

    /// Full-bleed single child: set its frame directly in `viewWillLayoutSubviews`
    /// rather than pinning edge constraints (see the root AGENTS.md convention).
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        host?.view.frame = view.bounds
    }

    private func embed(_ host: UIHostingController<ShareEvidenceView>) {
        self.host = host
        addChild(host)
        host.view.frame = view.bounds
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "com.stuff.where.share", code: NSUserCancelledError),
        )
    }
}
