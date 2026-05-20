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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.2.1-rc/LiveBuySDK.xcframework.zip",
            checksum: "fc9ad09dbf8e903e5af02b0450d210634f0fc819ca217d74a91f64290e6e9e5c"
        )
    ]
)
