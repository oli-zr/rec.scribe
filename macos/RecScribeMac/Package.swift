// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RecScribeMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RecScribeMac", targets: ["RecScribeMac"])
    ],
    targets: [
        .executableTarget(
            name: "RecScribeMac",
            path: "Sources/RecScribeMac"
        )
    ]
)
