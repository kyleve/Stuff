import Testing
import ViewDocumentCore

struct ViewAnimationDescriptorSamplingTests {
    @Test func delayEndpointsAndAutoreverseAreDeterministic() {
        let end = ViewAnimationDescriptor.Pose(
            opacity: 0.5,
            offsetX: 10,
            offsetY: 20,
            scaleX: 2,
            scaleY: 3,
            rotation: 90,
        )
        let animation = ViewAnimationDescriptor(
            from: .identity,
            to: end,
            staticPose: .identity,
            duration: 2,
            delay: 1,
            curve: .linear,
            repetition: .count(1, autoreverses: true),
        )
        #expect(animation.pose(at: 0) == .identity)
        #expect(animation.pose(at: 1) == .identity)
        #expect(animation.pose(at: 2).offsetX == 5)
        #expect(animation.pose(at: 3) == end)
        #expect(animation.pose(at: 4).offsetX == 5)
        #expect(!animation.isComplete(at: 4.99))
        #expect(animation.isComplete(at: 5))
        #expect(animation.pose(at: 5) == .identity)
        #expect(animation.pose(at: 100) == .identity)
    }

    @Test func onceHoldsFinalPoseAndForeverRestarts() {
        var end = ViewAnimationDescriptor.Pose.identity
        end.rotation = 90
        var animation = ViewAnimationDescriptor(
            from: .identity,
            to: end,
            staticPose: .identity,
            duration: 1,
            delay: 0,
            curve: .linear,
            repetition: .once,
        )
        #expect(animation.isComplete(at: 2))
        #expect(animation.pose(at: 2) == end)
        animation.repetition = .forever(autoreverses: false)
        #expect(!animation.isComplete(at: 100_000))
        #expect(animation.pose(at: 2.5).rotation == 45)
    }
}
