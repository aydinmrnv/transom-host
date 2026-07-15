// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "transom-host",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // The ONLY dependency. Ask before adding others (invariants I-8).
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        // Shared logic used by BOTH the CLI and the .app. The implementation is
        // never forked between the two executables; it lives here (issue Part 3).
        .target(
            name: "TransomKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The diagnostic CLI: `transom-host <subcommand>`.
        .executableTarget(
            name: "transom-host",
            dependencies: [
                "TransomKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                // Swift 6 language mode: complete strict concurrency checking.
                .swiftLanguageMode(.v6)
            ]
        ),
        // The SwiftUI probe app. Built as a bare executable here; wrapped into
        // `Transom Probe.app` (stable bundle id, own TCC identity) by
        // scripts/make-app.sh. See issue Part 2/3.
        .executableTarget(
            name: "TransomProbeApp",
            dependencies: [
                "TransomKit"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
