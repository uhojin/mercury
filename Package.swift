// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mercury",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Mercury",
            path: "Mercury",
            exclude: ["Resources/Info.plist", "Resources/Mercury.entitlements"]
        )
    ]
)
