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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.1-rc/LiveBuySDK.xcframework.zip",
            checksum: "5002664395cf108fb28894020e5789a7f741f084421d4642eee68f2130b951d4"
        )
    ]
)
