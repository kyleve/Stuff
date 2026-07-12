import LogKit
import SwiftUI
import UIKit
import WhereCore

/// Principal class for the Where share extension (see `Info.plist`'s
/// `NSExtensionPrincipalClass`). Hosts the SwiftUI `ShareEvidenceView` in a
/// `UIHostingController` and bridges its save/cancel actions to the extension
/// request lifecycle.
final class ShareViewController: UIViewController {
    private static let logger = WhereLog.channel(.shareExtension)

    override func viewDidLoad() {
        super.viewDidLoad()

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Self.logger.info("Share extension opened with \(items.count) item(s)")

        let model = ShareEvidenceModel(items: items)
        let root = ShareEvidenceView(
            model: model,
            onSave: { [weak self] in self?.complete() },
            onCancel: { [weak self] in self?.cancel() },
        )
        embed(UIHostingController(rootView: root))
    }

    private func embed(_ host: UIHostingController<ShareEvidenceView>) {
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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
