actor EvidenceTestActor {
    private(set) var readCount: Int64 = 0
    func read() -> Int64 {
        readCount += 1; return readCount
    }
}
