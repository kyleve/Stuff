import Foundation

enum FrameSizeCategory: String, CaseIterable, Identifiable, Sendable {
    case print = "Print"
    case social = "Social"

    var id: String { rawValue }
}

struct FrameSize: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let category: FrameSizeCategory
    let widthRatio: CGFloat
    let heightRatio: CGFloat

    var aspectRatio: CGFloat { widthRatio / heightRatio }
}

extension FrameSize {
    static let allSizes: [FrameSize] = [
        // Print
        .init(id: "4x6", label: "4 × 6", category: .print, widthRatio: 4, heightRatio: 6),
        .init(id: "5x7", label: "5 × 7", category: .print, widthRatio: 5, heightRatio: 7),
        .init(id: "8x10", label: "8 × 10", category: .print, widthRatio: 8, heightRatio: 10),
        .init(id: "11x14", label: "11 × 14", category: .print, widthRatio: 11, heightRatio: 14),
        // Social
        .init(id: "1:1", label: "Square (1:1)", category: .social, widthRatio: 1, heightRatio: 1),
        .init(id: "4:5", label: "Portrait (4:5)", category: .social, widthRatio: 4, heightRatio: 5),
        .init(id: "16:9", label: "Landscape (16:9)", category: .social, widthRatio: 16, heightRatio: 9),
        .init(id: "9:16", label: "Story (9:16)", category: .social, widthRatio: 9, heightRatio: 16),
    ]

    static func sizes(for category: FrameSizeCategory) -> [FrameSize] {
        allSizes.filter { $0.category == category }
    }
}
