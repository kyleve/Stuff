#if DEBUG
    import Foundation

    /// Counts and output details from a completed static export.
    public struct FlyoverExportSummary: Equatable, Sendable {
        public let screenCount: Int
        public let stateCount: Int
        public let profileCount: Int
        public let imageCount: Int
        public let outputByteCount: Int
        public let outputDirectory: URL

        public init(
            screenCount: Int,
            stateCount: Int,
            profileCount: Int,
            imageCount: Int,
            outputByteCount: Int,
            outputDirectory: URL,
        ) {
            self.screenCount = screenCount
            self.stateCount = stateCount
            self.profileCount = profileCount
            self.imageCount = imageCount
            self.outputByteCount = outputByteCount
            self.outputDirectory = outputDirectory
        }
    }
#endif
