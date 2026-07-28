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
        // NOTE: no SwiftPM test target on purpose — `swift test` needs XCTest or
        // swift-testing, and neither ships with the Command Line Tools this
        // project builds against. `scripts/test.sh` compiles Tests/ against the
        // real sources instead. See README § 개발용.
    ]
)
