// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacDirector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacDirector", targets: ["MacDirector"])
    ],
    dependencies: [
        // WebRTC Binaries para OSX/iOS
        .package(url: "https://github.com/stasel/WebRTC.git", from: "125.0.0"),
        // SwiftProtobuf para compilar los esquemas definidos
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0")
    ],
    targets: [
        .executableTarget(
            name: "MacDirector",
            dependencies: [
                "WebRTC",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/MacDirector",
            resources: [.process("Resources")]
        )
    ]
)
