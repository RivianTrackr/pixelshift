// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixelShift",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Self-updates for copies downloaded from the web (not used by the App Store build).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "ResizeCore"),
        .executableTarget(
            name: "PixelShift",
            dependencies: ["ResizeCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ResizeCoreTests", dependencies: ["ResizeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
