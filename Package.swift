// swift-tools-version: 5.9
import PackageDescription

// Livebuy iOS SDK — distribution package (v2.0.0+).
//
// THREE products (decision `ios-v2-release-readiness` D3):
//   • LivebuySDK         — headless core, a BINARY XCFramework (the IP moat:
//                          engine / networking / HMAC / IVS / state machine).
//                          Bundles the AWS IVS Player live engine (D2 option A).
//   • LivebuyUI          — zero-pixel view-model layer, shipped as SOURCE.
//   • LivebuyReferenceUI — drop-in / customizable pixel layer, shipped as SOURCE.
//
// Three-tier consumption (pick the products you need):
//   Tier 0  純 headless        →  LivebuySDK
//   Tier 1  綁 view-model 自畫  →  LivebuySDK + LivebuyUI
//   Tier 2  drop-in turnkey     →  + LivebuyReferenceUI
//
// IVS link invariant (D-A): the binary `LivebuySDK` references AWS IVS symbols,
// and a `.binaryTarget` cannot declare dependencies — so EVERY target that links
// `LivebuySDK` must carry `AmazonIVSPlayer` in its link closure. The `LivebuySDK`
// product lists both binary targets; the `LivebuyUI` / `LivebuyReferenceUI` source
// targets list `AmazonIVSPlayer` explicitly (even though their source never imports
// it), so Tier-1/2 consumers do not hit an undefined-symbol link error.
//
// `Sources/LivebuyUI` and `Sources/LivebuyReferenceUI` are SYNCED verbatim from the
// monorepo `ios/Sources/` by the release CI (single source of truth = monorepo).
let package = Package(
    name: "LivebuySDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "LivebuySDK", targets: ["LivebuySDK", "AmazonIVSPlayer"]),
        .library(name: "LivebuyUI", targets: ["LivebuyUI"]),
        .library(name: "LivebuyReferenceUI", targets: ["LivebuyReferenceUI"]),
    ],
    targets: [
        // Headless core — built by CI from the monorepo, vended as an XCFramework.
        .binaryTarget(
            name: "LivebuySDK",
            // Updated automatically by CI on each release.
            url: "https://github.com/ariesweng/livebuy-ios-sdk/releases/download/v4.0.0/LivebuySDK.xcframework.zip",
            checksum: "876537c559d8ec40d5231917bfb13a13d7ada5b1c9e2ce0cf2a5adfeb00ec224"
        ),
        // AWS IVS Player live engine (D2 option A — declared here pointing at AWS,
        // checksum-pinned at v1.52.0). The binary core links it; see the IVS link
        // invariant above.
        .binaryTarget(
            name: "AmazonIVSPlayer",
            url: "https://player.live-video.net/1.52.0/AmazonIVSPlayer.xcframework.zip",
            checksum: "c836cc04d8c5ec85a5720a7803092706266a65224a46130188314f4a972da700"
        ),
        // view-model layer (SOURCE; synced from monorepo ios/Sources/LivebuyUI by CI).
        // Depends on AmazonIVSPlayer for the binary-core IVS link closure (D-A).
        .target(
            name: "LivebuyUI",
            dependencies: ["LivebuySDK", "AmazonIVSPlayer"],
            path: "Sources/LivebuyUI"
        ),
        // reference-ui pixel layer (SOURCE; synced from monorepo ios/Sources/LivebuyReferenceUI by CI).
        .target(
            name: "LivebuyReferenceUI",
            dependencies: ["LivebuyUI", "LivebuySDK", "AmazonIVSPlayer"],
            path: "Sources/LivebuyReferenceUI"
        ),
    ]
)
