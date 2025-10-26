// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftScaffolding",
    platforms: [
        .macOS(.v13)
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
        )
    ]
)
