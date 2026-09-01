import CreditKit

enum SoftwareCreditsPresentation: Equatable {
    struct Loaded: Equatable {
        let libraries: [SoftwareCredit]
        let developmentTools: [SoftwareCredit]

        init(credits: [SoftwareCredit]) {
            libraries = credits.filter { $0.kind == .library }
            developmentTools = credits.filter { $0.kind == .developmentTool }
        }
    }

    case loaded(Loaded)
    case unavailable

    init(state: SoftwareCreditsLoadState) {
        switch state {
            case let .loaded(credits):
                self = .loaded(Loaded(credits: credits))
            case .failed:
                self = .unavailable
        }
    }
}
