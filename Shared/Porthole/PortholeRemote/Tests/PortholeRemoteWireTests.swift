import Foundation
@testable import PortholeRemote
import Testing

struct PortholeRemoteWireTests {
    @Test func framingRejectsUnboundedAndEmptyAllocations() throws {
        let data = Data(repeating: 42, count: 258)
        let frame = try PortholeRemoteFraming.frame(data)
        #expect(Array(frame.prefix(4)) == [0, 0, 1, 2])
        #expect(try PortholeRemoteFraming.size(Data(frame.prefix(4))) == data.count)
        #expect(frame.dropFirst(4) == data)
        #expect(throws: PortholeRemoteError.frameTooLarge) { try PortholeRemoteFraming.size(Data(
            repeating: 255,
            count: 4,
        )) }
        #expect(throws: PortholeRemoteError.invalidMessage) {
            try PortholeRemoteFraming.frame(Data())
        }
        #expect(throws: PortholeRemoteError.invalidMessage) {
            try PortholeRemoteFraming.size(Data([1]))
        }
    }

    @Test func wireCannotDecodeAnApprovalCommand() {
        let data = Data(
            "{\"version\":1,\"requestID\":\"00000000-0000-0000-0000-000000000001\",\"operation\":{\"approve\":{}}}"
                .utf8,
        )
        #expect(throws: (any Error).self) { try JSONDecoder().decode(
            PortholeRemoteRequest.self,
            from: data,
        ) }
    }
}
