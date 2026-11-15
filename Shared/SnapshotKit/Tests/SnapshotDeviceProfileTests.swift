import CoreGraphics
import SnapshotKit
import Testing

struct SnapshotDeviceProfileTests {
    @Test(arguments: SnapshotConfiguration.DeviceProfile.allCases)
    func rotationPreservesTheDisplayAndSelectsPhoneOrTabletTraits(
        profile: SnapshotConfiguration.DeviceProfile,
    ) throws {
        let portrait = profile.frame(orientation: .portrait)
        let landscape = profile.frame(orientation: .landscape)
        guard case let .fixed(portraitSize) = portrait.size,
              case let .fixed(landscapeSize) = landscape.size
        else { Issue.record("Device profiles require bounded viewports"); return }
        #expect(portraitSize.width < portraitSize.height)
        #expect(landscapeSize == CGSize(width: portraitSize.height, height: portraitSize.width))
        let traits = try #require(landscape.layoutTraits)
        #expect(traits.interfaceIdiom == profile.idiom)
        switch profile.idiom {
            case .phone:
                #expect(traits.verticalSizeClass == .compact)
                #expect(traits
                    .horizontalSizeClass == (profile == .iPhone17ProMax ? .regular : .compact))
            case .pad:
                #expect(traits.horizontalSizeClass == .regular)
                #expect(traits.verticalSizeClass == .regular)
        }
        #expect(portrait.name != landscape.name)
        if profile == .iPhone17 || profile == .iPhone17ProMax {
            #expect(landscape.safeAreaInsets.leading == portrait.safeAreaInsets.top)
            #expect(landscape.safeAreaInsets.trailing == portrait.safeAreaInsets.top)
        }
    }

    @Test func newDeviceIdentifiersDoNotCollideWithExistingFrames() {
        let configurations = SnapshotConfiguration.DeviceProfile.allCases.flatMap { profile in
            SnapshotConfiguration.DeviceProfile.Orientation.allCases.map {
                SnapshotConfiguration(device: profile.frame(orientation: $0))
            }
        }
        let identifiers = configurations.map(\.identifier)
        #expect(Set(identifiers).count == 12)
        #expect(!identifiers.contains(SnapshotConfiguration(device: .iPhone).identifier))
        #expect(!identifiers.contains(SnapshotConfiguration(device: .iPad).identifier))
    }
}
