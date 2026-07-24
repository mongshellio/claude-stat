// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mongshell-menubar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "mongshell-menubar",
            path: "Sources/mongshell-menubar"
        )
    ]
)
