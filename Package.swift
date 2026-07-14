// swift-tools-version: 5.9
import PackageDescription

// LiveBuy iOS SDK — distribution package (v2.0.0+).
//
// THREE products (decision `ios-v2-release-readiness` D3):
//   • LiveBuySDK         — headless core, a BINARY XCFramework (the IP moat:
//                          engine / networking / HMAC / IVS / state machine).
//                          Bundles the AWS IVS Player live engine (D2 option A).
//   • LiveBuyUI          — zero-pixel view-model layer, shipped as SOURCE.
//   • LiveBuyReferenceUI — drop-in / customizable pixel layer, shipped as SOURCE.
//
// Three-tier consumption (pick the products you need):
//   Tier 0  純 headless        →  LiveBuySDK
//   Tier 1  綁 view-model 自畫  →  LiveBuySDK + LiveBuyUI
//   Tier 2  drop-in turnkey     →  + LiveBuyReferenceUI
//
// IVS link invariant (D-A): the binary `LiveBuySDK` references AWS IVS symbols,
// and a `.binaryTarget` cannot declare dependencies — so EVERY target that links
// `LiveBuySDK` must carry `AmazonIVSPlayer` in its link closure. The `LiveBuySDK`
// product lists both binary targets; the `LiveBuyUI` / `LiveBuyReferenceUI` source
// targets list `AmazonIVSPlayer` explicitly (even though their source never imports
// it), so Tier-1/2 consumers do not hit an undefined-symbol link error.
//
// `Sources/LiveBuyUI` and `Sources/LiveBuyReferenceUI` are SYNCED verbatim from the
// monorepo `ios/Sources/` by the release CI (single source of truth = monorepo).
let package = Package(
    name: "LiveBuySDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "LiveBuySDK", targets: ["LiveBuySDK", "AmazonIVSPlayer"]),
        .library(name: "LiveBuyUI", targets: ["LiveBuyUI"]),
        .library(name: "LiveBuyReferenceUI", targets: ["LiveBuyReferenceUI"]),
    ],
    targets: [
        // Headless core — built by CI from the monorepo, vended as an XCFramework.
        .binaryTarget(
            name: "LiveBuySDK",
            // Updated automatically by CI on each release.
            url: "https://github.com/ariesweng/livebuy-ios-sdk/releases/download/v3.2.1-rc.1/LiveBuySDK.xcframework.zip",
            checksum: "a58952dd5e1e9f35c82a63d5408b6a2fca127398e605a761e9e43e41ada8b9ca"
        ),
        // AWS IVS Player live engine (D2 option A — declared here pointing at AWS,
        // checksum-pinned at v1.52.0). The binary core links it; see the IVS link
        // invariant above.
        .binaryTarget(
            name: "AmazonIVSPlayer",
            url: "https://player.live-video.net/1.52.0/AmazonIVSPlayer.xcframework.zip",
            checksum: "c836cc04d8c5ec85a5720a7803092706266a65224a46130188314f4a972da700"
        ),
        // view-model layer (SOURCE; synced from monorepo ios/Sources/LiveBuyUI by CI).
        // Depends on AmazonIVSPlayer for the binary-core IVS link closure (D-A).
        .target(
            name: "LiveBuyUI",
            dependencies: ["LiveBuySDK", "AmazonIVSPlayer"],
            path: "Sources/LiveBuyUI"
        ),
        // reference-ui pixel layer (SOURCE; synced from monorepo ios/Sources/LiveBuyReferenceUI by CI).
        .target(
            name: "LiveBuyReferenceUI",
            dependencies: ["LiveBuyUI", "LiveBuySDK", "AmazonIVSPlayer"],
            path: "Sources/LiveBuyReferenceUI",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
