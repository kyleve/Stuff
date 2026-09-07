import DaylightCore
import Foundation

/// A status retry is safe only while wall time and uptime agree within the same boot.
struct SubmissionClock: Codable {
    let date: Date
    let uptime: TimeInterval

    func validate(date currentDate: Date, uptime currentUptime: TimeInterval) throws {
        let wallElapsed = currentDate.timeIntervalSince(date)
        let elapsed = currentUptime - uptime
        guard wallElapsed >= 0, elapsed >= 0, max(wallElapsed, elapsed) < 3500,
              abs(wallElapsed - elapsed) < 5
        else {
            throw PublishingFailure.needsAttention(
                "The previous post may have succeeded. Check Mastodon before retrying; the clock or duplicate-protection window changed.",
            )
        }
    }
}
