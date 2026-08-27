# Transit protobuf sources

This directory stores the protocol sources for Throw's MTA realtime decoder.
`gtfs-realtime.proto` comes from the GTFS Realtime specification.
`gtfs-realtime-NYCT.proto` comes from the MTA developer resources.

The generated Swift files are in
`Throw/ThrowCore/Sources/Transit/Wire`. They use the SwiftProtobuf version that
`Package.resolved` pins. Regenerate both files together after a source or tool
change. Then restore the repository concurrency annotations on the generated
message storage classes, and run the architecture test.

Do not edit message fields in the generated Swift files. Do not expose a
generated message outside the MTA adapter.
