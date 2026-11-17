#if DEBUG
    import Observation
    import SnapshotKit
    import SwiftUI

    /// Ordinary previews keep one case per identity. Captures isolate the completion hook
    /// per configuration and create fresh presentation state for every panel and retry.
    @MainActor
    struct CalendarSnapshotCases {
        let awaitsLayout: Bool

        func snapshot(
            name: String,
            configurations: [SnapshotConfiguration],
            mode: CalendarPresentationState.Mode = .detail,
            includesThemes: Bool = false,
            @ViewBuilder content: @escaping @MainActor (CalendarPresentationState?) -> some View,
        ) -> [SnapshotCase] {
            let groups = awaitsLayout ? configurations.map { [$0] } : [configurations]
            var cases: [SnapshotCase] = []
            for configurations in groups {
                let readiness = awaitsLayout ? CalendarSnapshotReadiness(mode: mode) : nil
                let hook: (@MainActor () async -> Void)? = if let readiness {
                    { await readiness.waitForLayout() }
                } else {
                    nil
                }
                @ViewBuilder
                func build() -> some View {
                    if let readiness {
                        MountedCalendarSnapshot(readiness: readiness, content: content)
                    } else {
                        content(nil)
                    }
                }
                if includesThemes {
                    cases.append(whereThemeSnapshot(
                        name: name,
                        configurations: configurations,
                        measurementReadiness: awaitsLayout ? .immediate : .sameAsCapture,
                        onReadyToMeasure: hook,
                        content: build,
                    ))
                } else {
                    cases.append(whereSnapshot(
                        name: name,
                        configurations: configurations,
                        measurementReadiness: awaitsLayout ? .immediate : .sameAsCapture,
                        onReadyToMeasure: hook,
                        content: build,
                    ))
                }
            }
            return cases
        }
    }

    /// Retries reuse the root view value in a new host. Start empty so each mount
    /// creates its own presentation and models, then retain that content through rehosting.
    private struct MountedCalendarSnapshot<Content: View>: View {
        let readiness: CalendarSnapshotReadiness
        let content: @MainActor (CalendarPresentationState?) -> Content
        @State private var preparedContent: Content?

        var body: some View {
            Group {
                if let preparedContent { preparedContent } else { Color.clear }
            }
            .task {
                guard preparedContent == nil, !Task.isCancelled else { return }
                preparedContent = content(readiness.makePresentation())
            }
        }
    }

    @MainActor
    final class CalendarSnapshotReadiness {
        private let mode: CalendarPresentationState.Mode
        private var pendingPresentation: CalendarPresentationState?
        private var mountWaiter: AsyncStream<CalendarPresentationState>.Continuation?

        init(mode: CalendarPresentationState.Mode) {
            self.mode = mode
        }

        func makePresentation() -> CalendarPresentationState {
            let presentation = CalendarPresentationState(mode: mode)
            if let mountWaiter {
                mountWaiter.yield(presentation)
            } else {
                pendingPresentation = presentation
            }
            return presentation
        }

        func waitForLayout() async {
            guard let presentation = await nextPresentation() else { return }
            // The mounted month task reconciles the year and initial scroll commands
            // in one synchronous transaction. Observe that specific view's state.
            for await ready in Observations({ presentation.year != nil }) {
                if ready || Task.isCancelled { return }
            }
        }

        private func nextPresentation() async -> CalendarPresentationState? {
            if let pendingPresentation {
                self.pendingPresentation = nil
                return pendingPresentation
            }
            precondition(mountWaiter == nil, "Calendar measurement hooks must run serially")
            let (mounts, continuation) = AsyncStream.makeStream(
                of: CalendarPresentationState.self,
                bufferingPolicy: .bufferingOldest(1),
            )
            mountWaiter = continuation
            defer {
                mountWaiter = nil
                continuation.finish()
            }
            var iterator = mounts.makeAsyncIterator()
            return await iterator.next()
        }
    }

    #Preview {
        MountedCalendarSnapshot(readiness: CalendarSnapshotReadiness(
            mode: .detail,
        )) { presentation in
            CalendarContentView(
                report: PreviewSupport.loadedYearReportModel(),
                presentationState: presentation,
            )
        }
        .whereBroadwayRoot()
    }
#endif
