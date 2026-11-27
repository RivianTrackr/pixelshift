// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixelShift",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ResizeCore"),
        .executableTarget(name: "PixelShift", dependencies: ["ResizeCore"]),
        .testTarget(name: "ResizeCoreTests", dependencies: ["ResizeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
