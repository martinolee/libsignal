// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibSignalClient",
    platforms: [
        .macOS(.v10_15), .iOS(.v13),
    ],
    products: [
        .library(name: "LibSignalClient", targets: ["LibSignalClient"]),
    ],
    targets: [
        .binaryTarget(
            name: "SignalFfi",
            url: "https://github.com/martinolee/libsignal/releases/download/0.87.5/SignalFfi.xcframework.zip",
            checksum: "c03e856789a6f78b3a50ba03adf1c27ab40ec65b2aabf57959f1dbd90f089a0b"
        ),
        .target(
            name: "LibSignalClient",
            dependencies: ["SignalFfi"],
            path: "swift/Sources/LibSignalClient"
        ),
    ]
)
