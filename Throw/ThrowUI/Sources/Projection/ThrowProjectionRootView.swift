import SwiftUI

/// Gates production projection rendering on the process launch state.
public struct ThrowProjectionRootView: View {
    private let session: ThrowSession
    private let presentation: ProjectionPresentation

    public init(session: ThrowSession, presentation: ProjectionPresentation) {
        self.session = session
        self.presentation = presentation
    }

    public var body: some View {
        Group {
            switch session.launchState {
                case .loading, .failed:
                    Color.black
                        .ignoresSafeArea()
                case .onboarding, .ready:
                    ProjectionSurface(session: session, presentation: presentation)
            }
        }
        .background(Color.black)
    }
}
