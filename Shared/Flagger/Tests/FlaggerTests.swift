@_spi(FlaggerUI) @testable import Flagger
import Testing

struct FlaggerTests {
    @Test
    func liveFlagPersistsOnlyAnOverride() async throws {
        let flagger = try await makeFlagger()
        let flags = TestFlags()

        #expect(flagger.valueOrDefault(for: flags.liveBoolean) == false)
        try await flagger.set(true, for: flags.liveBoolean)
        #expect(flagger.valueOrDefault(for: flags.liveBoolean) == true)
        #expect(flagger.snapshots().first { $0.id == flags.liveBoolean.id }?
            .storedValue == .boolean(true))

        try await flagger.set(false, for: flags.liveBoolean)
        #expect(flagger.snapshots().first { $0.id == flags.liveBoolean.id }?.storedValue == nil)
    }

    @Test
    func concurrentWritesToDifferentFlagsKeepBothCachedValuesCurrent() async throws {
        let flagger = try await makeFlagger()
        let flags = TestFlags()

        for index in 0 ..< 100 {
            let boolean = index.isMultiple(of: 2) == false
            let string = String(index)
            async let booleanWrite: Void = flagger.set(boolean, for: flags.liveBoolean)
            async let stringWrite: Void = flagger.set(string, for: flags.liveString)
            try await (booleanWrite, stringWrite)

            #expect(try flagger.value(for: flags.liveBoolean) == boolean)
            #expect(try flagger.value(for: flags.liveString) == string)
        }
    }

    @Test
    func typedWriteRejectsAFlagWhoseTypeDoesNotMatchTheRegisteredID() async throws {
        let flagger = try await makeFlagger()
        let registeredFlag = TestFlags().liveBoolean
        let mismatchedFlag = Flag<String, LiveUpdating>(
            registeredFlag.id,
            name: "Mismatched",
            default: "default",
        )

        await #expect(throws: FlaggerFailure.self) {
            try await flagger.set("invalid", for: mismatchedFlag)
        }
        #expect(try flagger.value(for: registeredFlag) == false)
        #expect(flagger.snapshots().first { $0.id == registeredFlag.id }?.storedValue == nil)
    }

    @Test
    func firstReadValueFreezes() async throws {
        let flagger = try await makeFlagger()
        let flag = TestFlags().firstNumber

        #expect(try flagger.value(for: flag) == 1)
        try await flagger.setOverride(.number(2), for: flag.id)

        #expect(try flagger.value(for: flag) == 1)
        let snapshot = flagger.snapshots().first { $0.id == flag.id }
        #expect(snapshot?.storedValue == .number(2))
        #expect(snapshot?.effectiveValue == .number(1))
        #expect(snapshot?.isFrozen == true)
    }

    @Test
    func launchValueIsFrozenAtOpen() async throws {
        let flagger = try await makeFlagger()
        let flag = TestFlags().launchString
        try await flagger.setOverride(.string("next launch"), for: flag.id)

        #expect(try flagger.value(for: flag) == "default")
        #expect(flagger.snapshots().first { $0.id == flag.id }?.hasPendingChange == true)
    }

    @Test
    func liveValuesEmitCurrentAndUpdatedValues() async throws {
        let flagger = try await makeFlagger()
        let flag = TestFlags().liveBoolean
        let stream = flagger.values(for: flag)
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == false)
        try await flagger.set(true, for: flag)
        #expect(await iterator.next() == true)
    }

    @Test
    func sourceAndGroupMetadataReachSnapshots() async throws {
        let flagger = try await makeFlagger()
        let snapshot = try #require(flagger.snapshots().first)

        #expect(snapshot.source.id == TestFlagSource.id)
        #expect(snapshot.group.id == TestFlags.id)
    }

    @Test
    func onDiskOverrideSurvivesReopen() async throws {
        let url = temporaryStoreURL()
        let flag = TestFlags().liveBoolean
        do {
            let first = try await Flagger.open(sources: testSources, storage: .atURL(url))
            try await first.set(true, for: flag)
        }

        let reopened = try await Flagger.open(sources: testSources, storage: .atURL(url))
        #expect(try reopened.value(for: flag) == true)
    }

    @Test
    func invalidStoredTypeThrowsOrFallsBackAndEmitsFailure() async throws {
        let url = temporaryStoreURL()
        do {
            let writer = try await Flagger.open(sources: stringSources, storage: .atURL(url))
            try await writer.set("yes", for: StringFlags().liveBoolean)
        }

        let flagger = try await Flagger.open(sources: testSources, storage: .atURL(url))
        let flag = TestFlags().liveBoolean
        #expect(throws: FlaggerFailure.self) { try flagger.value(for: flag) }

        let failures = flagger.failures()
        var iterator = failures.makeAsyncIterator()
        #expect(flagger.valueOrDefault(for: flag) == false)
        let failure = await iterator.next()
        #expect(failure?.flagID == flag.id)
        #expect(flagger.snapshots().first { $0.id == flag.id }?.failure != nil)
    }
}
