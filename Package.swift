// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeTerm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeTerm", targets: ["ClaudeTerm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeTerm",
            dependencies: ["SwiftTerm"],
            path: "Sources/ClaudeTerm"
        ),
    ]
)
