// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftScaffolding",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftScaffolding",
            targets: ["SwiftScaffolding"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "SwiftScaffolding",
            dependencies: [
                .product(name: "SwiftyJSON", package: "SwiftyJSON")
            ]
        ),
        .testTarget(
            name: "SwiftScaffoldingTests",
            dependencies: ["SwiftScaffolding"]
        )
    ]
)
