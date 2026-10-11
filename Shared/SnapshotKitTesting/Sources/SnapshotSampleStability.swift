import Foundation

/// Compares standard-range, 8-bit render samples against one quiet-window anchor.
/// Native glass can alternate adjacent channel values without any content motion.
enum SnapshotSampleStability {
    static func matches(_ sample: Data?, anchor: Data?) -> Bool {
        guard let sample, let anchor, !sample.isEmpty,
              sample.count == anchor.count else { return false }
        if sample == anchor { return true }
        // One quantization unit only, on every channel. There is no changed-area
        // allowance. Never move the anchor after a match: a slow fade must not
        // accumulate a sequence of individually acceptable steps.
        return zip(sample, anchor).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
    }
}
