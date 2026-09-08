#if DEBUG
    /// Source and simulator metadata recorded with an export.
    public struct FlyoverExportBuild: Codable, Equatable, Sendable {
        public let commit: String
        public let dirty: Bool
        public let branch: String?
        public let generatedAt: String
        public let xcodeVersion: String
        public let simulatorDevice: String
        public let simulatorOS: String

        public init(
            commit: String,
            dirty: Bool,
            branch: String?,
            generatedAt: String,
            xcodeVersion: String,
            simulatorDevice: String,
            simulatorOS: String,
        ) {
            self.commit = commit
            self.dirty = dirty
            self.branch = branch
            self.generatedAt = generatedAt
            self.xcodeVersion = xcodeVersion
            self.simulatorDevice = simulatorDevice
            self.simulatorOS = simulatorOS
        }
    }
#endif
