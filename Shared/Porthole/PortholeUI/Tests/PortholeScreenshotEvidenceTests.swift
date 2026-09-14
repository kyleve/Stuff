import Foundation
import PortholeCore
@testable import PortholeUI
import Testing

@MainActor
struct PortholeScreenshotEvidenceTests {
    @Test func preservesTheFrozenImageWhileDebuggerCredentialsAreVisible() throws {
        let source = ScreenshotSource()
        let evidence = PortholeScreenshotEvidence(source: source) { source.presented }
        let original = try source.result.get()
        try evidence.freeze()
        source.result = .success(Data("credential-bearing debugger image".utf8))
        source.presented = true
        #expect(try evidence.png() == original)
        #expect(throws: PortholeError.self) { try evidence.freeze() }
        #expect(try evidence.png() == original)
        #expect(source.captures == 1)
    }

    @Test func refusesLiveCaptureWithoutFrozenEvidenceWhilePresented() throws {
        let source = ScreenshotSource()
        source.presented = true
        let evidence = PortholeScreenshotEvidence(source: source) { source.presented }
        #expect(throws: PortholeError.self) { try evidence.png() }
        #expect(source.captures == 0)
        source.presented = false
        #expect(try evidence.png() == source.result.get())
        #expect(source.captures == 1)
    }

    @Test func failedOrResetCaptureDoesNotFallBackToADebuggerImage() throws {
        let source = ScreenshotSource()
        let evidence = PortholeScreenshotEvidence(source: source) { source.presented }
        source.result = .failure(.unsupported("Window is unavailable"))
        #expect(throws: PortholeError.self) { try evidence.freeze() }
        source.result = .success(Data("debugger image".utf8))
        source.presented = true
        #expect(throws: PortholeError.self) { try evidence.png() }
        evidence.reset()
        #expect(throws: PortholeError.self) { try evidence.png() }
        #expect(source.captures == 1)
    }
}

@MainActor private final class ScreenshotSource: PortholeScreenshotCapturing {
    var result: Result<Data, PortholeError> = .success(Data("application image".utf8))
    var presented = false
    private(set) var captures = 0
    func capturePNG() throws -> Data {
        captures += 1; return try result.get()
    }
}
