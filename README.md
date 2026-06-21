# LiveBuy iOS SDK

Embed live shopping experiences — live streams, replays, and shoppable VODs — directly into your iOS app.

> **Architecture.** `LiveBuySDK` is a **headless** core (it renders no UI). The turnkey,
> ready-to-use UI ships as drop-in SwiftUI containers (`LiveBuyPlayer` / `LiveBuyWidget`)
> in the **`LiveBuyReferenceUI`** product. Most integrators add `LiveBuySDK` +
> `LiveBuyReferenceUI` and are done in a few lines. Teams that want to draw every pixel
> themselves use the headless core directly and compose their own views (see
> [Composing your own UI](#composing-your-own-ui)).

---

## Requirements

| | Minimum |
|---|---|
| iOS | 14.0 |
| Xcode | 15.0 |
| Swift | 5.9 |

---

## Installation

### Swift Package Manager (Xcode UI)

1. In Xcode, go to **File → Add Package Dependencies…**
2. Paste the repository URL:
   ```
   https://github.com/wpkc0429/livebuy-ios-sdk
   ```
3. Dependency Rule:
   - **Released versions** — **Up to Next Major Version** starting from `2.0.0`.
   - **Pre-release testing (release candidates)** — choose **Exact Version** and enter the
     rc tag, e.g. `2.0.0-rc.5`. SPM does not auto-resolve pre-releases from a range, so an
     `exact` pin is required.
4. Add the product(s) you need — pick any combination:
   - **LiveBuySDK** — headless core (always). Bundles the AWS IVS Player live engine.
   - **LiveBuyReferenceUI** — drop-in / customizable default UI (turnkey `LiveBuyPlayer` /
     `LiveBuyWidget` containers). Depends on the two below.
   - **LiveBuyUI** — zero-pixel view-model layer (only needed if you compose your own UI).

> ⚠️ **IVS binary.** Adding any product also resolves the `AmazonIVSPlayer` XCFramework
> (AWS, checksum-pinned at **v1.52.0**) — accept and pin it. It is the low-latency live
> engine; see the SDK distribution notes for the binary-trust + version-pin details.

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    // Released:    .package(url: "https://github.com/wpkc0429/livebuy-ios-sdk", from: "2.0.0")
    // Pre-release: pin the exact rc tag
    .package(url: "https://github.com/wpkc0429/livebuy-ios-sdk", exact: "2.0.0-rc.5")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            // headless core (always)
            .product(name: "LiveBuySDK", package: "livebuy-ios-sdk"),
            // drop-in default UI (most integrators want this)
            .product(name: "LiveBuyReferenceUI", package: "livebuy-ios-sdk"),
            // view-model layer — only if you compose your own UI:
            // .product(name: "LiveBuyUI", package: "livebuy-ios-sdk"),
        ]
    )
]
```

---

## Getting Started

### 1. Configure the SDK

Call `configure` once at app launch, before any SDK feature is used. It is `async throws`,
so call it from an async context.

```swift
import LiveBuySDK

// e.g. in a Task kicked off at launch
Task {
    try await LiveBuy.configure(
        apiKey: "12345",        // String (numeric string) — provided by LiveBuy
        secret: "your-secret",  // HMAC signing secret — provided by LiveBuy
        shopId: "Pw8PJ99J"      // required — provided by LiveBuy
    )
}
```

To attach a logged-in user so their name appears in chat:

```swift
try await LiveBuy.configure(
    apiKey: "12345",
    secret: "your-secret",
    shopId: "Pw8PJ99J",
    lang: "en",                                  // optional language override
    user: LBUser(displayName: "Alice", avatarUrl: nil)
)
```

### 2. Present the Player

`LiveBuyPlayer` is a turnkey **SwiftUI** container (`UIViewControllerRepresentable`). It
assembles the headless engine + the default chrome (header / rail / info panel / product +
chat overlays) and starts playback — in one line.

```swift
import SwiftUI
import LiveBuyReferenceUI

struct LivePage: View {
    var body: some View {
        LiveBuyPlayer(videoId: "abc123")
    }
}
```

From **UIKit**, wrap it in a hosting controller:

```swift
import SwiftUI
import LiveBuyReferenceUI

let vc = UIHostingController(rootView: LiveBuyPlayer(videoId: "abc123"))
present(vc, animated: true)
```

Wire interactions through `LiveBuyPlayerConfig` (every closure is optional with a sensible
default — pass nothing and it still works):

```swift
var config = LiveBuyPlayerConfig()
config.onProductTap = { _, product in
    // open your product detail page — product.id (String), product.name, product.goodsGpn
}
config.onLogin = {
    // open your login flow; on success call LiveBuy.login(...)
}
LiveBuyPlayer(videoId: "abc123", config: config)
```

### 3. Embed a Widget

`LiveBuyWidget` is a turnkey **SwiftUI** `View` listing a shop's videos.

```swift
import SwiftUI
import LiveBuyReferenceUI

LiveBuyWidget(shopId: "Pw8PJ99J")                  // horizontal carousel (default)
LiveBuyWidget(shopId: "Pw8PJ99J", mode: .grid)     // infinite-scroll grid
```

Tapping a card does nothing until you wire it (the container does not guess your
navigation):

```swift
var config = LiveBuyWidgetConfig()
config.onTapVideo = { video in
    // open your player page — video.id, video.title
}
config.onSeeMore = { /* push your “see all” page */ }
LiveBuyWidget(shopId: "Pw8PJ99J", mode: .grid, config: config)
```

From UIKit, wrap in `UIHostingController(rootView: LiveBuyWidget(...))` and add it as a
child as usual.

---

## SDK Reference

### LiveBuy

The main entry point. Must be configured before any other SDK call.

#### `configure(...)`

```swift
public static func configure(
    apiKey: String,
    secret: String,
    shopId: String,
    lang: String? = nil,
    user: LBUser? = nil,
    autoPipOnIntercept: Bool = true,
    apiVersion: Int = 1,
    configFetchTimeoutMs: Int = 5000
) async throws
```

| Parameter | Type | Description |
|---|---|---|
| `apiKey` | `String` | Your LiveBuy API key — a numeric string (e.g. `"12345"`). |
| `secret` | `String` | HMAC signing secret. Keep this private; avoid embedding it where it can be extracted from the binary. |
| `shopId` | `String` | Your shop identifier. Provided by LiveBuy. |
| `lang` | `String?` | Override the display language (see [Localization](#localization)). If `nil`, the API response language is used, falling back to `zh-TW`. |
| `user` | `LBUser?` | Logged-in user identity. `displayName` is shown in chat. If `nil`, the SDK generates a guest identity (`Guest_XXXX`). |
| `autoPipOnIntercept` | `Bool` | When `true` (default), the player enters Picture-in-Picture automatically if your listener intercepts a navigation event (`PRODUCT_CLICK`, `AUTH_REQUIRED`, `INFO_CUSTOMER_SERVICE`). |
| `apiVersion` | `Int` | Backend API major version. Default `1`; sent as the `X-API-Version` header. |
| `configFetchTimeoutMs` | `Int` | Max wait for the remote config fetch. Default `5000` ms. |

> Throws if the server rejects the HMAC signature. Other config-fetch failures are graceful:
> the SDK uses built-in fallback values and `configure` still returns.

#### Identity & runtime control

```swift
static func login(memberId: String, memberName: String? = nil) async throws
static func setUser(_ user: LBUser)
static func clearUser()
static func setGuestNickname(_ name: String)   // guest display name; NOT a login
static func setLanguage(_ lang: String)        // zh-TW / zh-CN / en / ms-MY / id-ID
static func setEventListener(_ listener: LiveBuyEventListener?)
```

Call after `configure(...)` to update identity when your user logs in / out / switches
accounts. `setUser` / `clearUser` are synchronous and non-blocking; side effects run in the
background. See [Reverse-Notification APIs](#reverse-notification-apis).

#### `notifyCheckoutCompleted(orderId:sdkTrackCodes:items:)`

```swift
static func notifyCheckoutCompleted(
    orderId: String,
    sdkTrackCodes: [String],
    items: [LBCheckoutItem]? = nil
)
```

Report a committed order to close the SDK-assisted purchase funnel. See
[Reverse-Notification APIs](#reverse-notification-apis).

#### `flushPendingEvents()`

```swift
static func flushPendingEvents() async throws -> LBFlushResult
```

Force-upload the offline event queue (bypasses backoff). Useful before logout or app
termination.

---

### LiveBuyPlayer (drop-in)

`import LiveBuyReferenceUI`. A turnkey SwiftUI player container.

```swift
public struct LiveBuyPlayer: UIViewControllerRepresentable {
    public init(videoId: String, config: LiveBuyPlayerConfig = LiveBuyPlayerConfig())
}
```

`LiveBuyPlayerConfig` — every field is optional with a documented default. The most common
seams:

| Field | Type | Default | Description |
|---|---|---|---|
| `eventListener` | `LiveBuyEventListener?` | none | Per-player event listener. |
| `onProductTap` | `((LiveBuyPlayerViewController, LBProduct) -> Void)?` | core product-tap flow | Product row / pinned-card tap. |
| `onLogin` | `(() -> Void)?` | inert | "前往登入" CTA on the login-gate modal → your login flow. The SDK never logs in by itself. |
| `onMinimize` | `(() -> Void)?` | core `minimize()` | Top-right minimize tap. |
| `onVideoSwitched` | `((String) -> Void)?` | none | Fires with the new video id after an in-place switch (hot-pick / watch-next / swipe). |

> Re-rendering `LiveBuyPlayer` with a different `videoId` reloads in place.

### LiveBuyWidget (drop-in)

`import LiveBuyReferenceUI`. A turnkey SwiftUI list/carousel.

```swift
public struct LiveBuyWidget: View {
    public init(shopId: String,
                mode: WidgetMode = .carousel,
                config: LiveBuyWidgetConfig = LiveBuyWidgetConfig())
}
```

`mode`: `.carousel` (horizontal) or `.grid` (infinite-scroll, 2-column).

`LiveBuyWidgetConfig`:

| Field | Type | Default | Description |
|---|---|---|---|
| `onTapVideo` | `((LBVideoItem) -> Void)?` | inert | Card tap — wire this to open your player. |
| `onSeeMore` | `(() -> Void)?` | inert | Carousel "查看更多 ›" header link. |
| `onVideosChanged` | `(([LBVideoItem]) -> Void)?` | none | Called after the first load with the ordered feed. |
| `eventListener` | `LiveBuyEventListener?` | none | Per-widget event listener. |
| `live` | `Bool` | `true` | Render real thumbnails at runtime. |
| `showsDemoFallbackWhenEmpty` | `Bool` | `false` | Show demo fixtures when the live fetch is empty (production-safe default = off). |
| `listRefreshInterval` | `TimeInterval` | `30` | List auto-refresh seconds (`0` = off). Distinct from the 5 s comment poll. |

---

### Data Models

#### `LBUser`

```swift
LBUser(displayName: "Alice", avatarUrl: "https://…/avatar.png", externalUserId: "u_001")
```

| Property | Type | Description |
|---|---|---|
| `displayName` | `String` | Name shown in live chat. |
| `avatarUrl` | `String?` | URL of the user's avatar image. |
| `externalUserId` | `String?` | Your own user identifier (optional). |

#### `LBPlayerState`

| Case | Description |
|---|---|
| `.loading` | Fetching channel metadata from the API |
| `.buffering` | Metadata received; waiting for enough stream data to begin |
| `.playing` | Stream is playing |
| `.paused` | Playback is paused |
| `.ended` | Stream ended; end screen is shown |
| `.error` | Unrecoverable error |

#### `LBProduct` (key fields)

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Internal product ID (String for cross-platform parity). |
| `goodsGpn` | `String` | Global product number — use this to look products up in your catalogue. |
| `name` | `String` | Display name. |
| `price` | `Double` | Current price. |
| `priceShow` | `String` | Formatted price string for display. |
| `soldOut` | `Int` | `1` if sold out, `0` otherwise. |
| `stock` | `Int` | Remaining stock count. |
| `pic` | `String` | Primary image URL. |

---

## Events

The SDK funnels every user interaction and system signal through a single listener,
`LiveBuyEventListener`. Install one listener and dispatch by `eventName`.

```swift
final class MyListener: NSObject, LiveBuyEventListener {
    func onEventTriggered(
        eventName: String,
        params: [String: Any],
        cartCallback: LBCartResultCallback?,
        shareContext: LBShareContext?
    ) -> Bool {
        switch eventName {
        case LBEvent.productClick:
            navigateToProduct(productId: params["product_id"] as! String)
            return true   // your app handles it; SDK skips its default UI
        case LBEvent.cartAddRequest:
            // resolve within 5 seconds
            cartCallback?.onSuccess(appTrackCode: "app_tr_001")
            return true
        default:
            return false  // SDK shows its default behaviour
        }
    }
}
LiveBuy.setEventListener(MyListener())
```

### Three dispatch semantics

| Type | Events | Listener returns | Threading |
|---|---|---|---|
| Notification | `VIDEO_OPEN`, `VIDEO_SWITCH`, `VIDEO_LIKE`, `VIDEO_COMMENT`, `VIDEO_SHARE`, `VIDEO_HEARTBEAT`, `INFO_PRODUCT_VIEW`, `COUPON_CLAIM`, `AUTH_STATE_CHANGED`, `LANGUAGE_CHANGED`, `CHECKOUT_COMPLETED` | Ignored | Background queue |
| Request / response | `CART_ADD_REQUEST` | Ignored — use `cartCallback` instead | Background queue; 5 s hard timeout |
| Sync interceptor | `AUTH_REQUIRED`, `PRODUCT_CLICK`, `VIDEO_SHARE_REQUEST`, `INFO_CUSTOMER_SERVICE` | `true` = your app handles it; `false` = SDK default UI | Calling thread |

### Cart flow

```text
user taps "Add to cart"
    └─► SDK freezes button + generates sdk_track_code
        └─► onEventTriggered("CART_ADD_REQUEST", params, cartCallback, nil)
            ├─► cartCallback.onSuccess(appTrackCode: "app_tr_xyz")   ─► success animation
            ├─► cartCallback.onFailure(errorCode: "OUT_OF_STOCK", message: "已售完")  ─► error toast
            └─► (no response within 5 s)                            ─► timeout toast
```

Collect each successful add-to-cart's `sdk_track_code` (from `params`) and pass them to
`notifyCheckoutCompleted` so the order can be attributed back to the SDK-assisted add.

### Auto-PiP on intercept

When the player is on screen, the intercepted event is `AUTH_REQUIRED` / `PRODUCT_CLICK` /
`INFO_CUSTOMER_SERVICE`, your listener returns `true`, and `autoPipOnIntercept` is left at
its default `true`, the player enters Picture-in-Picture as your screen takes over. If PiP
is unavailable (system setting off, missing `UIBackgroundModes: [audio]`, etc.) the SDK
silently pauses instead — no toast or alert.

> The full event catalogue (every `eventName`, its `params` keys, and the component-contract
> behaviour) is documented in the **component-contracts** spec — request it from LiveBuy.

---

## Reverse-Notification APIs

The host app communicates back into the SDK through methods on `LiveBuy`. Call them after
`configure(...)`.

### Membership integration — `setUser` / `clearUser` / `login`

```swift
// On login success:
try await LiveBuy.login(memberId: "u_001", memberName: "Alice")
LiveBuy.setUser(LBUser(displayName: "Alice", avatarUrl: nil, externalUserId: "u_001"))

// On logout:
LiveBuy.clearUser()
```

Synchronous side effects of `setUser` / `clearUser`:

1. Update internal identity (`clearUser` reverts to `Guest_XXXX`).
2. Reidentify the chat client; new chat messages use the new display name.
3. Dispatch `AUTH_STATE_CHANGED` to your listener.
4. If a pending auth action is still within its 30-second replay window, the original action
   is re-dispatched and its name appears in `AUTH_STATE_CHANGED.params.resumed_action`.

> **Login-flow recipe (auto-replay)** — In your listener, return `true` for `AUTH_REQUIRED`
> and push your login screen. On success call `LiveBuy.login(...)` then `LiveBuy.setUser(user)`;
> the SDK replays the blocked action without the user re-tapping. If the user abandons login,
> call `LiveBuy.clearUser()` to discard the pending action.

### Guest nickname — `setGuestNickname`

```swift
LiveBuy.setGuestNickname("小明")
```

Sets the display name a **guest** uses for chat. This is **not** a login — it does not flip
the user to logged-in or trigger auth replay. For logged-in users use `login` / `setUser`.

### Language switching — `setLanguage`

```swift
LiveBuy.setLanguage("en")   // zh-TW / zh-CN / en / ms-MY / id-ID
```

Overrides both `configure(lang:)` and the API's `lang` field, redraws visible UI, and
dispatches `LANGUAGE_CHANGED`. Unsupported values are logged and ignored.

### Checkout attribution — `notifyCheckoutCompleted`

```swift
LiveBuy.notifyCheckoutCompleted(
    orderId: "ord_001",
    sdkTrackCodes: ["sdk_tr_abc", "sdk_tr_def"],   // collected from CART_ADD_REQUEST params
    items: [
        LBCheckoutItem(productId: "p_999", quantity: 2,
                       price: NSDecimalNumber(string: "199.00"), currency: "TWD")
    ]
)
```

- `sdkTrackCodes` must be non-empty unless `items` is also non-empty.
- The SDK deduplicates the same `orderId` within 24 hours; idempotent retries are safe.
- Queued locally (offline-safe) and dispatched as `CHECKOUT_COMPLETED`.

### Force flush — `flushPendingEvents`

```swift
Task { try? await LiveBuy.flushPendingEvents() }   // e.g. before logout / on terminate
```

Bypasses backoff and uploads pending/failed events now, up to a 5-second ceiling.

---

## Composing your own UI

If you want to draw every button, list, and overlay yourself, depend on `LiveBuySDK`
(optionally `+ LiveBuyUI`) instead of `LiveBuyReferenceUI`. The headless core renders no
pixels: it gives you data buffers and the unified event listener; you turn user actions into
`simulate*` calls back into the SDK to keep its state in sync. The authoritative headless
contract — every event, state-machine sub-state, and component behaviour — is the
**component-contracts** spec. Request it from LiveBuy.

---

## Error Handling

Business and transport errors are represented by `LBError`:

| Case | Meaning |
|---|---|
| `.invalidSignature` | HMAC signature rejected — check `apiKey` / `secret` and the device clock. |
| `.videoNotFound` | The video id does not exist or is not accessible with your key. |
| `.restricted` | The video is geo-restricted or the viewer does not meet access requirements. |
| `.chatRateLimited` | Chat messages sent too quickly — throttle to ~1/second. |
| `.chatRequiresLogin` | Commenting requires login (`guest_comment == 0` for a guest) — drive `login(...)`. |
| `.guestNameTaken` | Guest display name already in use — prompt for a rename. |
| `.networkError(underlying:)` | A network-layer error — retry when connectivity returns. |
| `.serverError(code:message:)` | Unexpected backend error code. |
| `.loginFailed(code:message:)` | `login(...)` business failure. |
| `.sdkVersionUnsupported` | This SDK version is no longer accepted by the backend (upgrade). |

---

## Localization

Active language resolution priority:

1. `LiveBuy.setLanguage(_:)` at runtime — highest priority
2. `lang` passed to `LiveBuy.configure(lang:)`
3. `lang` returned by the API for the current video/shop
4. Fallback: `zh-TW`

| Code | Language |
|---|---|
| `zh-TW` | Traditional Chinese (default) |
| `zh-CN` | Simplified Chinese |
| `en` | English |
| `ms-MY` | Malay |
| `id-ID` | Indonesian |

---

## Info.plist Requirements

### Background Audio

To keep audio playing when the app is backgrounded, add `audio` to `UIBackgroundModes`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Or in Xcode: **Target → Signing & Capabilities → Background Modes → Audio, AirPlay, and
Picture in Picture**.

### Picture in Picture

PiP works on iOS 14+ with no additional Info.plist entry and is enabled by default. PiP
requires Background Modes → Audio to be enabled, otherwise it is silently unavailable.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

Copyright © LiveBuy. All rights reserved.
