enum SourceValidationState: Equatable {
    case untested
    case testing
    case succeeded
    case failed(ThrowFailureCategory)

    var isSuccessful: Bool {
        if case .succeeded = self { true } else { false }
    }
}
