import SwiftUI

struct PreviewProjectionView: View {
    let session: ThrowSession
    let outputID: ProjectionOutputID

    var body: some View {
        ProjectionSurface(session: session, presentation: .preview)
            .onAppear { session.projectionOutputConnected(.preview(outputID)) }
            .onDisappear { session.projectionOutputDisconnected(.preview(outputID)) }
    }
}
