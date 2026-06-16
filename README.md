# LiveBuy iOS SDK

Embed live shopping experiences — live streams, replays, and shoppable VODs — directly into your iOS app.

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
3. Select **Up to Next Major Version** starting from `2.0.0`
4. Add the product(s) you need — pick any combination:
   - **LiveBuySDK** — headless core (always). Bundles the AWS IVS Player live engine.
   - **LiveBuyUI** — zero-pixel view-model layer (if you compose your own UI).
   - **LiveBuyReferenceUI** — drop-in / customizable default UI (turnkey `LiveBuyPlayer` / `LiveBuyWidget` containers).

> ⚠️ **IVS binary.** Adding any product also resolves the `AmazonIVSPlayer` XCFramework
> (AWS, checksum-pinned at **v1.52.0**) — accept and pin it. It is the low-latency live
> engine; see the SDK distribution notes for the binary-trust + version-pin details.

### Swift Package Manager (Package.swift)

Three-tier consumption — depend on the products you need:

```swift
dependencies: [
    .package(url: "https://github.com/wpkc0429/livebuy-ios-sdk", from: "2.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            // Tier 0 — headless core (always)
            "LiveBuySDK",
            // Tier 1 — zero-pixel view-model layer (compose your own UI)
            // .product(name: "LiveBuyUI", package: "livebuy-ios-sdk"),
            // Tier 2 — drop-in / customizable default UI
            // .product(name: "LiveBuyReferenceUI", package: "livebuy-ios-sdk"),
        ]
    )
]
```

---

## Getting Started

### 1. Configure the SDK

Call `configure` once at app launch, before any SDK feature is used.

```swift
// AppDelegate.swift
import LiveBuySDK

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    LiveBuy.configure(
        apiKey: 12345,          // Int — provided by LiveBuy
        secret: "your-secret"   // String — provided by LiveBuy
    )
    return true
}
```

To attach a logged-in user so their name appears in chat:

```swift
LiveBuy.configure(
    apiKey: 12345,
    secret: "your-secret",
    lang: "en",                              // optional language override
    user: LBUser(displayName: "Alice", avatarUrl: nil)
)
```

### 2. Present the Player

```swift
import LiveBuySDK

let player = LiveBuyPlayerViewController()

// Handle product taps from the player
player.onProductTap = { product in
    print("Tapped:", product.name, product.goodsGpn)
    // Navigate to your product detail page
}

present(player, animated: true) {
    player.load(videoId: "abc123")
}
```

### 3. Embed a Widget

```swift
import LiveBuySDK

let widget = LiveBuyWidget(shopId: "shop-001", mode: .carousel)
widget.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(widget)

NSLayoutConstraint.activate([
    widget.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    widget.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    widget.heightAnchor.constraint(equalToConstant: 300)
])
```

---

## SDK Reference

### LiveBuySDK

The main entry point. Must be configured before any other SDK call.

#### `configure(apiKey:secret:lang:user:autoPipOnIntercept:)`

```swift
static func configure(
    apiKey: Int,
    secret: String,
    lang: String? = nil,
    user: LBUser? = nil,
    autoPipOnIntercept: Bool = true
)
```

| Parameter | Type | Description |
|---|---|---|
| `apiKey` | `Int` | Your LiveBuy API key. Provided by LiveBuy as an integer. |
| `secret` | `String` | HMAC signing secret. Keep this value private; do not expose it in client-side code that can be extracted. |
| `lang` | `String?` | Override the display language. See [Localization](#localization) for supported codes. If `nil`, the language from the API response is used, falling back to `zh-TW`. |
| `user` | `LBUser?` | Logged-in user identity. `displayName` is shown in the live chat. If `nil`, the SDK generates a guest identity (`Guest_XXXX`). |
| `autoPipOnIntercept` | `Bool` | When `true` (default), the SDK enters Picture-in-Picture automatically if your listener intercepts a player navigation event (`PRODUCT_CLICK`, `AUTH_REQUIRED`, `INFO_CUSTOMER_SERVICE`). Set `false` to keep the player paused on the same screen instead. See [Events](#events). |

#### `setUser(_:)` / `clearUser()`

```swift
static func setUser(_ user: LBUser)
static func clearUser()
```

Call after `configure(...)` to update the SDK's identity when the host app's user logs in / out / switches accounts. Both methods are synchronous and non-blocking; internal side effects run on a background thread. See [Reverse-Notification APIs](#reverse-notification-apis).

#### `setLanguage(_:)`

```swift
static func setLanguage(_ lang: String)
```

Switch the SDK display language at runtime. See [Reverse-Notification APIs](#reverse-notification-apis).

#### `setEventListener(_:)`

```swift
static func setEventListener(_ listener: LiveBuyEventListener?)
```

Install a single global listener that receives every SDK event. See [Events](#events).

#### `notifyCheckoutCompleted(orderId:sdkTrackCodes:items:)`

```swift
static func notifyCheckoutCompleted(
    orderId: String,
    sdkTrackCodes: [String],
    items: [LBCheckoutItem]? = nil
)
```

Report a completed order to close the SDK-assisted purchase funnel. See [Reverse-Notification APIs](#reverse-notification-apis).

#### `flushPendingEvents()`

```swift
static func flushPendingEvents() async throws -> LBFlushResult
```

Force-upload the offline event queue (bypasses backoff). Useful before logout or app termination. See [Reverse-Notification APIs](#reverse-notification-apis).

---

### LiveBuyPlayerViewController

A full-screen `UIViewController` that plays live streams, replays, and VODs. Handles buffering, PiP, background audio, polling, and product overlays automatically.

#### Configuration Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `showChat` | `Bool` | `true` | Show the live chat overlay |
| `showProducts` | `Bool` | `true` | Show the product list panel |
| `enablePiP` | `Bool` | `true` | Enable Picture-in-Picture when the user backgrounds the app |
| `autoDismissDelay` | `Int` | `5` | Seconds to wait on the end screen before auto-playing the next video |

#### Callbacks

Set these before calling `load(videoId:)`.

```swift
// Player state changed
player.onStateChange = { state in
    // state: LBPlayerState (.loading, .buffering, .playing, .paused, .ended, .error)
}

// User tapped a product in the overlay
player.onProductTap = { product in
    // product: LBProduct — open your product detail screen
}

// New poll data arrived (chat messages, rush events, live-end signal)
player.onPollReceived = { response in
    // response: LBPollResponse
}

// An error occurred
player.onError = { error in
    // error: LBError
}
```

#### Methods

| Method | Description |
|---|---|
| `load(videoId: String)` | Fetch channel metadata and start playback. Clears any existing video token. Safe to call multiple times to switch videos. |
| `play()` | Resume playback. |
| `pause()` | Pause playback. |
| `setMuted(_ muted: Bool)` | Mute or unmute the player. The player starts muted; the first tap unmutes. |
| `seek(seconds: Double)` | Seek to a position in seconds. Only available for replays (`liveStatus == 3`). |
| `sendChat(message: String)` | Post a chat message to the live stream. |

---

### LiveBuyWidget

An embeddable `UIView` that shows a list or carousel of LiveBuy videos. Tapping a card opens the full-screen player automatically (or calls your `onVideoTap` handler if provided).

#### Carousel / Grid

```swift
// Horizontal scrolling carousel
let carousel = LiveBuyWidget(shopId: "shop-001", mode: .carousel)

// Infinite-scroll 2-column grid
let grid = LiveBuyWidget(shopId: "shop-001", mode: .grid)
grid.columns = 3   // optional: change column count

// Custom tap handler (overrides default player presentation)
carousel.onVideoTap = { video in
    print("Tapped:", video.id, video.title)
}
```

#### Floating Mini-Player

```swift
// Draggable floating widget anchored to a video
let floating = LiveBuyWidget(
    videoId: "abc123",
    mode: .floating,
    width: 225,    // optional, default 225 pt
    height: 400    // optional, default 400 pt
)

floating.onClose = {
    floating.removeFromSuperview()
}
```

#### Widget Modes

| Mode | Behaviour |
|---|---|
| `.carousel` | Horizontally scrolling card row with left/right arrow buttons. Suitable for embedding in a scroll view row. |
| `.grid` | Vertically scrolling grid with infinite pagination. Suitable for a dedicated video listing screen. |
| `.floating` | Draggable mini-player for a single video, anchored to a corner of its container. |

#### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `columns` | `Int` | `2` | Column count in `.grid` mode |
| `floatingWidth` | `CGFloat` | `225` | Width of the floating window in points |
| `floatingHeight` | `CGFloat` | `400` | Height of the floating window in points |

#### Callbacks

| Callback | Signature | Description |
|---|---|---|
| `onVideoTap` | `((LBVideoItem) -> Void)?` | Called when a card is tapped. If `nil`, the SDK presents `LiveBuyPlayerViewController` automatically. |
| `onClose` | `(() -> Void)?` | Called when the user closes a `.floating` widget. |

---

### Data Models

#### `LBUser`

```swift
LBUser(displayName: "Alice", avatarUrl: "https://…/avatar.png")
```

| Property | Type | Description |
|---|---|---|
| `displayName` | `String?` | Name shown in live chat |
| `avatarUrl` | `String?` | URL of the user's avatar image |

#### `LBPlayerState`

| Case | Description |
|---|---|
| `.loading` | Fetching channel metadata from the API |
| `.buffering` | Metadata received; waiting for enough stream data to begin |
| `.playing` | Stream is playing |
| `.paused` | Playback is paused |
| `.ended` | Stream ended; end screen is shown |
| `.error` | Unrecoverable error; `onError` is also fired |

#### `LBProduct` (key fields)

| Property | Type | Description |
|---|---|---|
| `id` | `Int` | Internal product ID |
| `goodsGpn` | `String` | Global product number (e.g. `"P456"`) — use this as the identifier to look up products in your catalogue |
| `name` | `String` | Display name |
| `price` | `Double` | Current price |
| `priceShow` | `String` | Formatted price string for display (e.g. `"NT$299"`) |
| `soldOut` | `Int` | `1` if sold out, `0` otherwise |
| `stock` | `Int` | Remaining stock count |
| `pic` | `String` | Primary image URL |

---

## Events

The SDK funnels every user interaction and system signal through a single listener interface, `LiveBuyEventListener`. Install one listener (per app, not per Widget) and dispatch by `eventName`.

```swift
LiveBuy.setEventListener(self)

extension MainViewController: LiveBuyEventListener {
    func onEventTriggered(
        eventName: String,
        params: [String: Any],
        cartCallback: LBCartResultCallback?,
        shareContext: LBShareContext?
    ) -> Bool {
        switch eventName {
        case LBEvent.productClick:
            navigateToProduct(productId: params["product_id"] as! String)
            return true   // SDK skips its built-in product detail page
        case LBEvent.cartAddRequest:
            addToCart(params, callback: cartCallback!)
            return true   // SDK keeps the button in loading state until cartCallback fires
        default:
            return false  // SDK shows its default behaviour
        }
    }
}
```

### Three dispatch semantics

| Type | Events | Listener returns | Threading |
|---|---|---|---|
| Notification | `VIDEO_OPEN`, `VIDEO_SWITCH`, `VIDEO_LIKE`, `VIDEO_COMMENT`, `VIDEO_SHARE`, `VIDEO_HEARTBEAT`, `INFO_PRODUCT_VIEW`, `COUPON_CLAIM`, `AUTH_STATE_CHANGED`, `LANGUAGE_CHANGED`, `CHECKOUT_COMPLETED` | Ignored | Background queue |
| Request / response | `CART_ADD_REQUEST` | Ignored — use `cartCallback` instead | Background queue; 5 s hard timeout |
| Sync interceptor | `AUTH_REQUIRED`, `PRODUCT_CLICK`, `VIDEO_SHARE_REQUEST`, `INFO_CUSTOMER_SERVICE` | `true` = your app handles it; `false` = SDK shows default UI | Calling thread |

### Event catalogue

Every event is one of the constants on `LBEvent`. The constant value is the `eventName` string passed to your listener.

| Constant | `eventName` | `params` keys | Notes |
|---|---|---|---|
| `LBEvent.videoOpen` | `VIDEO_OPEN` | `video_id`, `title` | |
| `LBEvent.videoSwitch` | `VIDEO_SWITCH` | `from_video_id`, `to_video_id` | |
| `LBEvent.videoLike` | `VIDEO_LIKE` | `video_id`, `current_likes` | |
| `LBEvent.videoComment` | `VIDEO_COMMENT` | `video_id`, `message` | |
| `LBEvent.videoShare` | `VIDEO_SHARE` | `video_id` | Fires *after* the user completes a share. |
| `LBEvent.videoHeartbeat` | `VIDEO_HEARTBEAT` | `video_id`, `progress_percent`, `duration` | Every 5 s (config-tunable) + 25 / 50 / 75 / 100 % checkpoints. |
| `LBEvent.infoProductView` | `INFO_PRODUCT_VIEW` | `video_id`, `product_id` | |
| `LBEvent.couponClaim` | `COUPON_CLAIM` | `video_id`, `coupon_id` | |
| `LBEvent.cartAddRequest` | `CART_ADD_REQUEST` | `video_id`, `product_id`, `sdk_track_code` | Use `cartCallback.onSuccess(appTrackCode:)` / `onFailure(...)` within 5 s. |
| `LBEvent.authRequired` | `AUTH_REQUIRED` | `trigger_action` (`"cart_add"` / `"comment_send"` / `"coupon_claim"`) | Return `true` to push your login flow. Call `LiveBuy.setUser(...)` within 30 s to auto-replay the blocked action. |
| `LBEvent.productClick` | `PRODUCT_CLICK` | `product_id`, `video_id` | Auto-PiP candidate. |
| `LBEvent.videoShareRequest` | `VIDEO_SHARE_REQUEST` | (empty) | Modify `shareContext.shareUrl` / `shareContext.title` to override SDK share content. |
| `LBEvent.infoCustomerService` | `INFO_CUSTOMER_SERVICE` | `video_id`, `anchor_id` | Auto-PiP candidate. |
| `LBEvent.authStateChanged` | `AUTH_STATE_CHANGED` | `state`, `display_name`, `external_user_id`, `resumed_action` | Fired in response to `setUser` / `clearUser`. |
| `LBEvent.languageChanged` | `LANGUAGE_CHANGED` | `from`, `to` | Fired in response to `setLanguage`. |
| `LBEvent.checkoutCompleted` | `CHECKOUT_COMPLETED` | `order_id`, `sdk_track_codes`, `item_count` | Fired in response to `notifyCheckoutCompleted`. |

### Cart flow

```text
user taps "Add to cart"
    └─► SDK freezes button + generates sdk_track_code
        └─► onEventTriggered("CART_ADD_REQUEST", params, cartCallback, nil)
            ├─► cartCallback.onSuccess("app_tr_xyz")  ───► SDK shows success animation
            ├─► cartCallback.onFailure("OUT_OF_STOCK", "已售完") ───► SDK shows error toast
            └─► (no response within 5 s)             ───► SDK shows "timeout" toast
```

The SDK persists the result locally (`sdk_track_code`, `app_track_code`, status) so that `notifyCheckoutCompleted` can later attribute the order back to the SDK-assisted add-to-cart.

### Auto-PiP on intercept

When *all* of the following hold, the player automatically enters Picture-in-Picture as your listener takes over the screen:

1. Source is `LiveBuyPlayerViewController` (Widget cells never trigger PiP).
2. Event is `AUTH_REQUIRED`, `PRODUCT_CLICK`, or `INFO_CUSTOMER_SERVICE`.
3. Listener returns `true`.
4. `configure(autoPipOnIntercept:)` is left at the default `true`.

If PiP is unavailable (system setting off, missing `UIBackgroundModes: [audio]`, etc.) the SDK silently calls `player.pause()` and records an `auto_pip_fallback` metric. No toast or alert is shown.

### Crash sandbox

Every call into your listener is wrapped in a `try-catch` (and bridged through Objective-C to catch `NSException`). Exceptions raised inside your handler are logged as `handled_exception` and uploaded in the background — they will **not** propagate to the host app.

---

## Reverse-Notification APIs

The host app communicates back into the SDK through four methods on `LiveBuy`. Call them after `configure(...)`; calling earlier throws `LBNotConfiguredError`.

### Membership integration — `setUser` / `clearUser`

```swift
LiveBuy.setUser(
    LBUser(displayName: "Alice", avatarUrl: nil, externalUserId: "u_001")
)

// On logout:
LiveBuy.clearUser()
```

Synchronous side effects:

1. Update internal identity (`clearUser` reverts to `Guest_XXXX`).
2. Clear `VideoTokenStore` so the next `Player.load(videoId:)` re-acquires a token.
3. Reidentify the chat client; new chat messages use the new display name.
4. Dispatch `AUTH_STATE_CHANGED` to your listener.
5. If a `PendingAuthAction` is still within its 30-second replay window, the original action is re-dispatched and its name appears in `AUTH_STATE_CHANGED.params.resumed_action`.

> **Login-flow recipe (auto-replay)** — In your listener, return `true` for `AUTH_REQUIRED` and push your login screen. When login succeeds, call `LiveBuy.setUser(user)`. The SDK replays the blocked `CART_ADD_REQUEST` (or whichever action triggered the auth gate) without the user re-tapping. If the user abandons login, calling `LiveBuy.clearUser()` discards the pending action instead.

> **Auth loop signal** — If `AUTH_REQUIRED` fires three times in the same widget session without an intervening `setUser`, the SDK emits an `auth_loop_suspected` metric. Treat this as a hint that your login completion callback is missing a `setUser(...)` call.

### Language switching — `setLanguage`

```swift
LiveBuy.setLanguage("en")
```

| Argument | Behaviour |
|---|---|
| `"zh-TW"`, `"zh-CN"`, `"en"`, `"ms-MY"`, `"id-ID"` | Updates `LBI18n.currentLocale`, redraws every visible Widget / Player on the main queue, dispatches `LANGUAGE_CHANGED` with `{ "from": <prev>, "to": <new> }`. |
| Any other value | Logged as a warning and ignored. No state change, no event. |

The value passed here **overrides** both `configure(lang:)` and the `lang` field returned by the API — once set, the SDK stays in that locale until you call `setLanguage` again.

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

Call **after the order is committed** in your checkout flow. Required guarantees:

- `sdkTrackCodes` MUST be non-empty unless `items` is also non-empty. Passing both empty drops the call and emits a `client_misuse` metric — most often this means your checkout integration forgot to harvest `sdk_track_code` from each successful `CART_ADD_REQUEST`.
- The SDK deduplicates the same `orderId` within 24 hours; idempotent retries are safe.
- The event is queued locally (offline-safe) and dispatched as `CHECKOUT_COMPLETED` to your listener.

### Force flush — `flushPendingEvents`

```swift
// Call before logout or before the app is force-terminated:
Task {
    let result = try await LiveBuy.flushPendingEvents()
    switch result.status {
    case "completed":           // every pending event uploaded
    case "partial", "timeout":  // 5-second budget hit; result.remainingCount > 0
    case "network_unavailable": // returns within ~100 ms; no upload attempted
    default: break
    }
}
```

`flushPendingEvents` bypasses the SDK's exponential-backoff schedule and uploads every `pending` / `failed` event right now, up to a 5-second hard ceiling. Concurrent callers share the same in-flight `Future` (the result is identical for every awaiter). Calling it more than 10 times in a 60-second window emits a `flush_abuse` metric, but the call is still honoured.

Typical recipes:

- Before logout: `try? await LiveBuy.flushPendingEvents()` then `LiveBuy.clearUser()`.
- On `applicationWillTerminate`: fire-and-forget `Task { try? await LiveBuy.flushPendingEvents() }`.

---

## Error Handling

```swift
player.onError = { error in
    switch error {
    case .invalidSignature:
        // The HMAC signature was rejected by the server.
        // Check that apiKey and secret are correct and that the device clock is accurate.
    case .signatureExpired:
        // The request timestamp is older than 600 seconds.
        // Ensure the device time is synchronised (NTP).
    case .videoNotFound:
        // The videoId does not exist or is not accessible with your API key.
    case .restricted:
        // The video is geo-restricted or the viewer does not meet access requirements.
        // Show an appropriate message and dismiss the player.
    case .chatRateLimited:
        // The user is sending chat messages too quickly.
        // Throttle your sendChat calls to at most one per second.
    case .networkError(let underlying):
        // A network-layer error occurred (no connectivity, timeout, etc.).
        // Inspect `underlying` for details; retry when connectivity is restored.
    case .serverError(let code, let message):
        // The API returned an unexpected error code.
        // Log `code` and `message` for debugging; display a generic error to the user.
    }
}
```

---

## Localization

The SDK UI is fully localised. The active language is resolved in this priority order:

1. **`LiveBuy.setLanguage(_:)`** at runtime — highest priority (see [Reverse-Notification APIs](#reverse-notification-apis))
2. **`lang` parameter** passed to `LiveBuy.configure(lang:)`
3. **`lang` field** returned by the API for the current video/shop
4. **Fallback:** `zh-TW`

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

To allow the player to continue playing audio when the user backgrounds your app, add `audio` to `UIBackgroundModes`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Or in Xcode: **Target → Signing & Capabilities → Background Modes → Audio, AirPlay, and Picture in Picture**.

### Picture in Picture

PiP works on iOS 14+ with no additional Info.plist entry. It is enabled by default (`enablePiP = true`). To disable it, set `player.enablePiP = false` before calling `load(videoId:)`.

> **Note:** PiP requires that Background Modes → Audio is also enabled, otherwise PiP will be silently unavailable.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

Copyright © LiveBuy. All rights reserved.
