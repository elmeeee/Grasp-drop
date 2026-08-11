// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Grasp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GraspExecutable", targets: ["Grasp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "NDHackery",
            path: "Sources/NDHackery",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "Grasp",
            dependencies: [
                "NDHackery",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftECC", package: "SwiftECC")
            ],
            path: "Sources/Grasp"
        )
    ]
)
