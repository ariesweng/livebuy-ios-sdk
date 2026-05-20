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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.0.3-rc/LiveBuySDK.xcframework.zip",
            checksum: "a68b6438e9913a3582223e7246c818fa60074fecc08f4bb3b49f853c04dbf548"
        )
    ]
)
