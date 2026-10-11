import UniformTypeIdentifiers

extension UTType {
    /// Encrypted Where backup container. The payload is a ZIP, but its custom
    /// extension prevents it from being mistaken for a plaintext manual export.
    static let whereBackup = UTType(
        exportedAs: "com.stuff.where.encrypted-backup",
        conformingTo: .zip,
    )
}
