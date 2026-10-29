// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GolfKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GolfKit", targets: ["GolfKit"])
    ],
    targets: [
        .target(name: "GolfKit"),
        .testTarget(
            name: "GolfKitTests",
            dependencies: ["GolfKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
