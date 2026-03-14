enum FramingMode: String, CaseIterable, Identifiable, Sendable {
    case cropToFill = "Crop to Fill"
    case fitWithMat = "Fit with Mat"

    var id: String { rawValue }
}
