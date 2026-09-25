// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MermaidSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Mermaid", targets: ["Mermaid"]),
    ],
    targets: [
        .target(name: "Mermaid"),
        .testTarget(name: "MermaidTests", dependencies: ["Mermaid"]),
    ]
)
