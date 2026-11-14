// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GuessASketch",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "GuessASketch", targets: ["GuessASketch"])],
    targets: [
        .target(name: "SketchCore"),
        .executableTarget(name: "GuessASketch", dependencies: ["SketchCore"]),
        .testTarget(name: "SketchCoreTests", dependencies: ["SketchCore"])
    ]
)
