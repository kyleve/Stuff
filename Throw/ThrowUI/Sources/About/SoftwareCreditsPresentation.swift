import CreditKit

struct SoftwareCreditsPresentation: Equatable {
    let libraries: [SoftwareCredit]
    let developmentTools: [SoftwareCredit]

    init(credits: [SoftwareCredit]) {
        libraries = credits.filter { $0.kind == .library }
        developmentTools = credits.filter { $0.kind == .developmentTool }
    }
}
