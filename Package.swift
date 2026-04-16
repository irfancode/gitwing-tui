// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitWing",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "gitwing",
            targets: ["App"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/soyer/ansipars.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [],
            path: "Sources/App"
        ),
        .target(
            name: "Views",
            dependencies: [],
            path: "Sources/Views"
        ),
        .target(
            name: "Models",
            dependencies: [],
            path: "Sources/Models"
        ),
        .target(
            name: "Services",
            dependencies: [],
            path: "Sources/Services"
        ),
        .target(
            name: "UI",
            dependencies: [],
            path: "Sources/UI"
        )
    ]
)