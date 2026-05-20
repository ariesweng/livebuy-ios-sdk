// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveBuySDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "LiveBuySDK", targets: ["LiveBuySDK"])
    ],
    targets: [
        .binaryTarget(
            name: "LiveBuySDK",
            // Updated automatically by CI on each release.
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.0-rc/LiveBuySDK.xcframework.zip",
            checksum: "c41ff06acc941cc1213a64c3a4bd6554e55ea221f5f68fe2a211c8eab899f964"
        )
    ]
)
