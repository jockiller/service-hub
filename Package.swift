// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ServiceHub",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ServiceHub", targets: ["ServiceHub"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3")
    ],
    targets: [
        .executableTarget(
            name: "ServiceHub",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/ServiceHub"
        )
    ]
)
