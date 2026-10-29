import Testing
import ViewDocumentCore

struct ViewDocumentValidatorTests {
    @Test func rejectsUnknownOperationsWithTheirPath() {
        let json = #"{"schemaVersion":1,"root":{"id":"bad","content":{"button":{}},"modifiers":[],"accessibility":{"automatic":{}}}}"#
        let error = #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument.decode(
                .init(json.utf8),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(error?.path.contains("content") == true)
    }

    @Test func rejectsUnorderedGradientStops() {
        let paint = ViewPaint.linearGradient(
            stops: [
                .init(color: .semantic(.primary), location: 0.8),
                .init(color: .semantic(.secondary), location: 0.2),
            ],
            start: .init(x: 0, y: 0),
            end: .init(x: 1, y: 1),
        )
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: documentNode(
                    "root",
                    content: .shape(.circle),
                    modifiers: [.foreground(paint)],
                )),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
    }

    @Test func enforcesAnimationBudgetAndDuration() {
        var animation = ViewAnimationDescriptor(
            from: .identity,
            to: .identity,
            staticPose: .identity,
            duration: 1,
            delay: 0,
            curve: .linear,
            repetition: .forever(autoreverses: true),
        )
        let limits = ViewDocumentLimits(bytes: 10000, depth: 16, nodes: 256, animatedNodes: 0)
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: documentNode(
                    "root",
                    content: .shape(.circle),
                    animation: animation,
                )),
                resources: noDocumentResources,
                limits: limits,
            )
        }
        animation.duration = 0
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: documentNode(
                    "root",
                    content: .shape(.circle),
                    animation: animation,
                )),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
    }
}
