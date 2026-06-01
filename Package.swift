// swift-tools-version:6.0
import PackageDescription

// Murmur is split into a library (MurmurKit) holding all logic so it can be
// unit-tested, and a thin executable (Murmur) that only bootstraps the app.
let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MurmurKit",
            path: "Sources/MurmurKit"
        ),
        .executableTarget(
            name: "Murmur",
            dependencies: ["MurmurKit"],
            path: "Sources/Murmur"
        ),
        .testTarget(
            name: "MurmurTests",
            dependencies: ["MurmurKit"],
            path: "Tests/MurmurTests"
        ),
    ]
)
