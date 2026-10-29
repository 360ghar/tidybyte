// swift-tools-version: 6.0

import PackageDescription

/// `APP_STORE=1 swift build -Xswiftc -DAPP_STORE --scratch-path .build/app-store-scratch` builds the sandboxed
/// channel. Direct builds update themselves through Sparkle.
let appStore = Context.environment["APP_STORE"] == "1"

let package = Package(
    name: "Tidybyte",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "MacOSCleanerCore", targets: ["MacOSCleanerCore"]),
        .executable(name: "Tidybyte", targets: ["MacOSCleaner"]),
        .executable(name: "tidybyte-mcp", targets: ["MacOSCleanerMCP"])
    ],
    dependencies: appStore ? [] : [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")],
    targets: [
        .target(
            name: "MacOSCleanerCore",
            path: "Sources/MacOSCleanerCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "MacOSCleanerAppKit",
            dependencies: ["MacOSCleanerCore"],
            path: "Sources/MacOSCleanerAppKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "MacOSCleaner",
            dependencies: ["MacOSCleanerCore", "MacOSCleanerAppKit"]
                + (appStore ? [] : [.product(name: "Sparkle", package: "Sparkle")]),
            path: "Sources/MacOSCleaner",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "MacOSCleanerMCPLibrary",
            dependencies: ["MacOSCleanerCore"],
            path: "Sources/MacOSCleanerMCPLibrary",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "MacOSCleanerMCP",
            dependencies: ["MacOSCleanerCore", "MacOSCleanerMCPLibrary"],
            path: "Sources/MacOSCleanerMCP",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MacOSCleanerTests",
            // The MCP server logic lives in a library target: test bundles
            // cannot link against an executable target under xcodebuild.
            dependencies: ["MacOSCleanerCore", "MacOSCleanerAppKit", "MacOSCleanerMCPLibrary"],
            exclude: [
                "UserStories/UX/UX_USER_BEHAVIOR_TEST_CASES.md",
                "UserStories/UX/README.md"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
