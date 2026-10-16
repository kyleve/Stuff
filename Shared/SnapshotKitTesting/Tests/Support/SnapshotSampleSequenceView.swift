import UIKit

/// Makes each fingerprint render advance one sample, independent of timer cadence.
@MainActor
final class SnapshotSampleSequenceView: UIView {
    private let samples: [UInt8]
    private(set) var renderCount = 0

    init(samples: [UInt8]) {
        precondition(samples.isEmpty == false)
        self.samples = samples
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates _: Bool) -> Bool {
        let value = CGFloat(samples[renderCount % samples.count]) / 255
        renderCount += 1
        UIColor(red: value, green: value, blue: value, alpha: 1).setFill()
        UIRectFill(rect)
        return true
    }
}
