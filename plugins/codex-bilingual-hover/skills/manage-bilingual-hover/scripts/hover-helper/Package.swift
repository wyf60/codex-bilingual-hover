// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexHoverTranslator",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "CodexHoverTranslator",
            path: "Sources/CodexHoverTranslator"
        )
    ],
    swiftLanguageModes: [.v5]
)
