#if DEBUG
    import CoreGraphics
    import Foundation

    /// The versioned data model consumed by a generated Flyover website.
    public struct FlyoverWebManifest: Codable, Sendable {
        public let schemaVersion: Int
        public let application: Application
        public let build: FlyoverExportBuild
        public let profiles: [Profile]
        public let canvas: Canvas
        public let groups: [Group]
        public let screens: [Screen]
        public let routes: [Route]
        public let images: [Image]

        public struct Application: Codable, Sendable {
            public let id: String
            public let title: String
        }

        public struct Profile: Codable, Sendable {
            public let id: String
            public let title: String
            public let device: String
            public let orientation: String
            public let colorScheme: String
            public let dynamicType: String
            public let contrast: String
            public let layoutDirection: String
            public let legibilityWeight: String
            public let snapshotType: String
        }

        public struct Canvas: Codable, Sendable {
            public let size: Size
            public let initialFitSize: Size
            public let groupFrames: [IdentifiedFrame]
            public let depthBandFrames: [DepthBandFrame]
            public let screenFrames: [IdentifiedFrame]
            public let connectors: [Connector]
        }

        public struct Group: Codable, Sendable {
            public let id: String
            public let title: String
            public let order: Int
            public let rootScreenID: String
            public let screenIDs: [String]
        }

        public struct Screen: Codable, Sendable {
            public let id: String
            public let title: String
            public let groupID: String
            public let groupOrder: Int
            public let screenOrder: Int
            public let viewport: Viewport
            public let navigationContainer: String
            public let frame: Rect
            public let variants: [Variant]
            public let incomingRouteIDs: [String]
            public let outgoingRouteIDs: [String]
        }

        public struct Viewport: Codable, Sendable {
            public let kind: String
            public let fixedSize: Size?
        }

        public struct Variant: Codable, Sendable {
            public let id: String
            public let title: String
            public let captureExtent: String
            public let imagesByProfile: [String: String]
        }

        public struct Route: Codable, Sendable {
            public let id: String
            public let sourceScreenID: String
            public let destinationScreenID: String
            public let kind: String
            public let label: String?
            public let geometry: ConnectorGeometry
        }

        public struct Image: Codable, Sendable {
            public let screenID: String
            public let variantID: String
            public let profileID: String
            public let relativePath: String
            public let pointWidth: Double
            public let pointHeight: Double
            public let pixelWidth: Int
            public let pixelHeight: Int
            public let scale: Double
            public let captureExtent: String
        }

        public struct IdentifiedFrame: Codable, Sendable {
            public let id: String
            public let frame: Rect
        }

        public struct DepthBandFrame: Codable, Sendable {
            public let groupID: String
            public let kind: String
            public let depth: Int?
            public let frame: Rect
        }

        public struct Connector: Codable, Sendable {
            public let routeID: String
            public let geometry: ConnectorGeometry
        }

        public struct ConnectorGeometry: Codable, Sendable {
            public let start: Point
            public let end: Point
            public let firstControl: Point
            public let secondControl: Point
            public let firstArrowPoint: Point
            public let secondArrowPoint: Point
        }

        public struct Rect: Codable, Equatable, Sendable {
            public let x: Double
            public let y: Double
            public let width: Double
            public let height: Double

            init(_ value: CGRect) {
                x = Double(value.origin.x)
                y = Double(value.origin.y)
                width = Double(value.size.width)
                height = Double(value.size.height)
            }
        }

        public struct Point: Codable, Equatable, Sendable {
            public let x: Double
            public let y: Double

            init(_ value: CGPoint) {
                x = Double(value.x)
                y = Double(value.y)
            }
        }

        public struct Size: Codable, Equatable, Sendable {
            public let width: Double
            public let height: Double

            init(_ value: CGSize) {
                width = Double(value.width)
                height = Double(value.height)
            }
        }
    }
#endif
