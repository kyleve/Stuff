import Foundation

public protocol LocationSampleRepository: Sendable {
    func availableYears() async -> [Int]
    func samples(in year: Int) async -> [LocationSample]
    func upsert(_ samples: [LocationSample]) async
}
