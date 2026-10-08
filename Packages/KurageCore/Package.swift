// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KurageCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "KurageCore", targets: ["KurageCore"]),
    ],
    targets: [
        .target(
            name: "KurageCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
