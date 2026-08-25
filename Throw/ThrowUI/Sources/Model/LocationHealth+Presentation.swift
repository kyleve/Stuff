extension LocationHealth {
    var isAcceptable: Bool {
        switch self {
            case .confirmed, .stale: true
            case .missing, .locating, .offeredBest, .failed: false
        }
    }
}
