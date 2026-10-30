import Foundation
import Testing
import ViewDocumentCore

struct ViewDocumentValidatorTests {
    @Test func amplifiedPaddingCannotExceedTheGeometryBudget() throws {
        var modifiers: [ViewModifierDescriptor] = [
            .frame(width: .points(100_000), height: .points(100_000), alignment: .center),
        ]
        modifiers += Array(repeating: .padding(.points(100_000)), count: 5)
        modifiers += [
            .background(shape: .rectangle, paint: .color(.semantic(.primary))),
            .scale(x: 100, y: 100),
            .scale(x: 10, y: 10),
        ]
        let document = ViewDocument(
            schemaVersion: 1,
            root: documentNode("padded", content: .shape(.rectangle), modifiers: modifiers),
        )
        let error = #expect(throws: ViewDocumentValidationError.self) {
            _ = try ValidatedViewDocument.decode(
                JSONEncoder().encode(document),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(error?.reason == "Combined authored geometry exceeds the rendering budget")
    }

    @Test func amplifiedChildFramesShareTheGeometryBudget() throws {
        let children = (0 ..< 20).map { index in
            documentNode("child-\(index)", content: .shape(.rectangle), modifiers: [
                .frame(width: .points(100_000), height: .points(100_000), alignment: .center),
            ])
        }
        var root = documentNode(
            "root",
            content: .group(axis: .horizontal, alignment: .center, spacing: 0, children: children),
        )
        _ = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: root),
            resources: noDocumentResources,
            limits: .standard,
        )
        root.modifiers = [.scale(x: 100, y: 100), .scale(x: 10, y: 10)]
        let error = #expect(throws: ViewDocumentValidationError.self) {
            _ = try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: root),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(error?.path == "$.root.children[1].modifiers[0]")
    }

    @Test func rejectsRepeatedScalesBeforeNativeRendering() throws {
        // Five individually valid scales make a clipped 2-point shape disappear in SwiftUI.
        let document = ViewDocument(schemaVersion: 1, root: documentNode(
            "shape",
            content: .shape(.rectangle),
            modifiers: [.frame(width: .points(2), height: .points(2), alignment: .center)]
                + Array(repeating: .scale(x: 100, y: 100), count: 5),
        ))
        let error = #expect(throws: ViewDocumentValidationError.self) {
            _ = try ValidatedViewDocument(
                document: document,
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(error?.reason == "Combined scale exceeds the supported amplification")
        #expect(throws: ViewDocumentValidationError.self) {
            _ = try ValidatedViewDocument.decode(
                JSONEncoder().encode(document),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
    }

    @Test func scaleBudgetFollowsAncestorsAndDoesNotCombineSiblings() throws {
        let first = documentNode(
            "first",
            content: .shape(.circle),
            modifiers: [.scale(x: 100, y: 100)],
        )
        let second = documentNode(
            "second",
            content: .shape(.circle),
            modifiers: [.scale(x: 100, y: 100)],
        )
        var root = documentNode(
            "root",
            content: .group(
                axis: .overlay,
                alignment: .center,
                spacing: 0,
                children: [first, second],
            ),
        )
        _ = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: root),
            resources: noDocumentResources,
            limits: .standard,
        )
        root.modifiers = [.scale(x: 100, y: 100)]
        let error = #expect(throws: ViewDocumentValidationError.self) {
            _ = try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: root),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(error?.path == "$.root.children[0].modifiers[0]")
    }

    @Test func everyAnimationPoseContributesToScaleBudget() throws {
        let poses: [WritableKeyPath<ViewAnimationDescriptor, ViewAnimationDescriptor.Pose>] = [
            \.from,
            \.to,
            \.staticPose,
        ]
        for pose in poses {
            var animation = ViewAnimationDescriptor(
                from: .identity,
                to: .identity,
                staticPose: .identity,
                duration: 1,
                delay: 0,
                curve: .linear,
                repetition: .once,
            )
            animation[keyPath: pose].scaleX = 100
            let root = documentNode(
                "root",
                content: .shape(.circle),
                modifiers: [.scale(x: 20, y: 20)],
                animation: animation,
            )
            let error = #expect(throws: ViewDocumentValidationError.self) {
                _ = try ValidatedViewDocument(
                    document: .init(schemaVersion: 1, root: root),
                    resources: noDocumentResources,
                    limits: .standard,
                )
            }
            #expect(error?.path == "$.root.animation")
        }
    }

    @Test func moderateScaleAndScaleDownRemainValid() throws {
        let root = documentNode("root", content: .shape(.circle), modifiers: [
            .scale(x: 10, y: -10),
            .scale(x: 0.1, y: 0.1),
            .scale(x: 10, y: 10),
        ])
        _ = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: root),
            resources: noDocumentResources,
            limits: .standard,
        )
    }

    @Test func boundsModifierNestingAndTotalWork() throws {
        var root = documentNode(
            "root",
            content: .text(""),
            modifiers: Array(repeating: .opacity(1), count: 32),
        )
        _ = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: root),
            resources: noDocumentResources,
            limits: .standard,
        )
        root.modifiers.append(.opacity(1))
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: root),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        let child = documentNode("child", content: .text(""), modifiers: [.opacity(1)])
        root = documentNode(
            "root",
            content: .group(axis: .overlay, alignment: .center, spacing: 0, children: [child]),
            modifiers: [.opacity(1)],
        )
        var limits = ViewDocumentLimits.standard
        limits.modifiers = 2
        _ = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: root),
            resources: noDocumentResources,
            limits: limits,
        )
        limits.modifiers = 1
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: root),
                resources: noDocumentResources,
                limits: limits,
            )
        }
    }

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
        let limits = ViewDocumentLimits(
            bytes: 10000,
            depth: 16,
            nodes: 256,
            animatedNodes: 0,
            modifiersPerNode: 32,
            modifiers: 1024,
        )
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
