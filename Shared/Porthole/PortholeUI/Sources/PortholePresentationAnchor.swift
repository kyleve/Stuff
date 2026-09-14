import SwiftUI
#if canImport(UIKit)
    import UIKit

    extension View {
        /// Attach once to the application root. Presentation follows this view's own window,
        /// including a sheet that already covers the application content.
        public func portholePresentationAnchor(controller: PortholePresentationController)
            -> some View
        {
            background {
                PortholePresentationAnchor(controller: controller, sessionID: controller.sessionID)
                    .id(ObjectIdentifier(controller))
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A window-scoped bridge; it never searches application-global scenes or windows.
    struct PortholePresentationAnchor: UIViewControllerRepresentable {
        let controller: PortholePresentationController
        let sessionID: UUID?

        func makeCoordinator() -> Coordinator {
            Coordinator(controller: controller)
        }

        func makeUIViewController(context: Context) -> AnchorController {
            let anchor = AnchorController()
            anchor.available = { [weak coordinator = context.coordinator, weak anchor] in
                guard let anchor else { return }
                coordinator?.synchronize(anchor: anchor)
            }
            return anchor
        }

        func updateUIViewController(_ anchor: AnchorController, context: Context) {
            context.coordinator.synchronize(anchor: anchor)
        }

        static func dismantleUIViewController(
            _ anchor: AnchorController,
            coordinator: Coordinator,
        ) {
            anchor.available = nil
            coordinator.detach()
        }

        final class AnchorController: UIViewController {
            var available: (() -> Void)?
            override func loadView() {
                view = UIView()
                view.backgroundColor = .clear
                view.isUserInteractionEnabled = false
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                available?()
            }
        }

        final class HostingController: UIHostingController<PortholeView> {
            var disappeared: (() -> Void)?
            private var leavingPresentation = false

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                leavingPresentation = false
            }

            override func viewWillDisappear(_ animated: Bool) {
                super.viewWillDisappear(animated)
                leavingPresentation = isBeingDismissed || presentingViewController?
                    .isBeingDismissed == true
            }

            override func viewDidDisappear(_ animated: Bool) {
                super.viewDidDisappear(animated)
                if leavingPresentation || presentingViewController == nil { disappeared?() }
            }
        }

        @MainActor
        final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate,
            PortholePresentationObserving
        {
            private struct Presentation {
                let sessionID: UUID
                let host: HostingController
            }

            private enum State {
                case idle
                case presenting(Presentation)
                case presented(Presentation)
                case dismissing(Presentation)
            }

            private let controller: PortholePresentationController
            private weak var anchor: AnchorController?
            private weak var window: UIWindow?
            private var state = State.idle
            private var awaitingTransition = false

            init(controller: PortholePresentationController) {
                self.controller = controller
                super.init()
                controller.registerPresentationObserver(self)
            }

            func portholePresentationDidChange() {
                synchronize()
            }

            func synchronize(anchor: AnchorController) {
                self.anchor = anchor
                if let window = anchor.viewIfLoaded?.window { self.window = window }
                synchronize()
            }

            private func synchronize() {
                switch state {
                    case .idle:
                        guard let sessionID = controller.sessionID,
                              anchor != nil,
                              let window, !window.isHidden,
                              let root = window.rootViewController else { return }
                        let presenter = Self.topmost(from: root)
                        if let transition = presenter.transitionCoordinator {
                            guard !awaitingTransition else { return }
                            awaitingTransition = true
                            let registered = transition
                                .animate(alongsideTransition: nil) { [weak self] _ in
                                    guard let self else { return }
                                    awaitingTransition = false
                                    Task { @MainActor [weak self] in self?.synchronize() }
                                }
                            if !registered { awaitingTransition = false }
                            else { return }
                        }
                        guard !presenter.isBeingPresented, !presenter.isBeingDismissed,
                              presenter.viewIfLoaded?.window === window else { return }
                        let host = HostingController(rootView: PortholeView(controller: controller))
                        host.modalPresentationStyle = .pageSheet
                        host.disappeared = { [weak self] in
                            // UIKit clears its presenter relationship after the disappearance
                            // callback. Reconcile on the next actor turn, after that teardown.
                            Task { @MainActor [weak self] in
                                self?.externallyDismissed(sessionID: sessionID)
                            }
                        }
                        let presentation = Presentation(sessionID: sessionID, host: host)
                        state = .presenting(presentation)
                        host.presentationController?.delegate = self
                        // UIKit owns this completion until presentation ends. Keep the
                        // coordinator alive so a detached anchor can still remove its sheet.
                        presenter.present(host, animated: true) { [self] in
                            guard case let .presenting(current) = state,
                                  current.sessionID == sessionID else { return }
                            state = .presented(current)
                            synchronize()
                        }
                    case let .presented(presentation):
                        guard controller.sessionID != presentation.sessionID || anchor == nil
                        else { return }
                        dismiss(presentation)
                    case .presenting, .dismissing:
                        break
                }
            }

            func detach() {
                controller.unregisterPresentationObserver(self)
                anchor = nil
                window = nil
                switch state {
                    case let .presented(presentation): dismiss(presentation)
                    case .idle: controller.dismiss()
                    case .presenting, .dismissing: break
                }
            }

            private func dismiss(_ presentation: Presentation) {
                state = .dismissing(presentation)
                presentation.host.dismiss(animated: anchor != nil) { [self] in
                    finished(sessionID: presentation.sessionID)
                }
            }

            private func finished(sessionID: UUID) {
                switch state {
                    case .idle: return
                    case let .presenting(current), let .presented(current),
                         let .dismissing(current):
                        guard current.sessionID == sessionID else { return }
                        current.host.disappeared = nil
                }
                state = .idle
                if controller.sessionID == sessionID { controller.dismiss() }
                synchronize()
            }

            private func externallyDismissed(sessionID: UUID) {
                switch state {
                    case let .presenting(current), let .presented(current):
                        guard current.sessionID == sessionID else { return }
                        finished(sessionID: sessionID)
                    case .idle, .dismissing:
                        // An owned dismissal has its own completion. Do not present its
                        // replacement while UIKit is still removing the previous sheet.
                        break
                }
            }

            func presentationControllerDidDismiss(
                _ presentationController: UIPresentationController,
            ) {
                switch state {
                    case .idle: break
                    case let .presenting(current), let .presented(current),
                         let .dismissing(current):
                        guard current.host === presentationController.presentedViewController
                        else { return }
                        finished(sessionID: current.sessionID)
                }
            }

            private static func topmost(from root: UIViewController) -> UIViewController {
                var result = root
                while let presented = result.presentedViewController {
                    result = presented
                }
                return result
            }
        }
    }
#endif
