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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.5-rc/LiveBuySDK.xcframework.zip",
            checksum: "8ebe2cac1fd6ad8523cd1000436bc89644037de01ab5e373bc60fffe06e4d889"
        )
    ]
)
