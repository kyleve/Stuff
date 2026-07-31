import SwiftUI
import WhereSurface

struct WhereMenuBarView: View {
    let model: WhereMenuBarModel

    var body: some View {
        Group {
            switch model.state {
                case let .unavailable(reason):
                    WhereMenuBarUnavailableView(reason: reason)
                case let .loaded(generatedAt, snapshot, refreshFailed):
                    WhereMenuBarSnapshotView(
                        generatedAt: generatedAt,
                        snapshot: snapshot,
                        refreshFailed: refreshFailed,
                    )
            }
        }
        .frame(width: 320)
        .padding()
    }
}
