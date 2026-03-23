// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeTerm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeTerm", targets: ["ClaudeTerm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/letsur-dev/SwiftTerm.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeTerm",
            dependencies: ["SwiftTerm"],
            path: "Sources/ClaudeTerm"
        ),
    ]
)
