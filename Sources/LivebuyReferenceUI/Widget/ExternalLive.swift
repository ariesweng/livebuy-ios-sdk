import Foundation
import UIKit
import LivebuySDK

// MARK: - External-platform live detection (rb-ios-external-live-watch)
//
// Spec: `external-live-watch/spec.md`.
//
// The shop's latest live can be an externally-hosted broadcast (a Facebook live).
// The backend returns it as an `LBVideoItem` whose `liveurl` is a `facebook.com`
// page (verified dev shop `Pw8PJ99J`, video `7epqqM`:
// `liveurl=https://www.facebook.com/.../videos/...`) — none of the SDK playback
// engines can play that. The FB URL exists ONLY on the widget-layer
// `LBVideoItem.liveurl`; the in-app player loads `/sdk/video`, whose `path` is a
// livebuy MP4 with no `liveurl`/`source`, so detection MUST happen here (the
// widget card / tap-routing layer) before the player opens.

enum ExternalLive {

    /// Hosts whose lives are watched on their own platform (NOT in-app). Each
    /// entry matches the host itself and any sub-domain (`m.`/`www.`). Extend
    /// this list to add YouTube / Instagram live later.
    static let hosts: [String] = ["facebook.com", "fb.watch", "fb.gg"]

    /// Whether `urlString` points at an external broadcast platform — a PURE,
    /// POSITIVE host allowlist. NEVER a negative "not `.m3u8`" rule: the backend
    /// may legitimately return a non-`.m3u8` MP4/VOD `liveurl` for a normal
    /// in-app video (per `widget-live-nested-decode`), so a negative rule would
    /// misclassify those and break in-app playback.
    ///
    /// Sub-domain match is anchored on a leading dot (`host == base` OR
    /// `host.hasSuffix("." + base)`) so look-alikes like `facebook.com.evil.example`
    /// and `notfacebook.com` do NOT match.
    ///
    /// **Scheme gate (`rb-url-exit-policy-gate`)**: the string is first run through the
    /// core `LBURLOpenPolicy.decide(_:)` allowlist — a `nil` decision (custom app
    /// scheme / `intent` / `file` / `javascript` / …) is NEVER an external live, even
    /// when its host is `facebook.com`. A live URL must additionally be a web scheme
    /// (`http` / `https`); `mailto` / `tel` / `sms` are openable but are not lives.
    /// The host check runs on the policy's parsed `decision.url` (one parser, no
    /// parser differential).
    static func isExternalLiveURL(_ urlString: String) -> Bool {
        externalLiveDecision(urlString) != nil
    }

    /// The core policy decision for `urlString` when it is an external live, else `nil`.
    /// Callers open `decision.url` (never re-parse the raw string).
    static func externalLiveDecision(_ urlString: String) -> LBURLOpenDecision? {
        guard let decision = LBURLOpenPolicy.decide(urlString),
              let scheme = decision.url.scheme?.lowercased(),
              webSchemes.contains(scheme),
              let host = decision.url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return hosts.contains { base in host == base || host.hasSuffix("." + base) }
            ? decision : nil
    }

    /// Schemes an external live URL may use (a subset of the core openable allowlist).
    static let webSchemes: Set<String> = ["http", "https"]
}

public extension LBVideoItem {

    /// The external-platform watch URL when this live's `liveurl` is an external
    /// broadcast (Facebook today), else `nil`. Tapping such a live opens this URL
    /// externally instead of the in-app player.
    ///
    /// The returned URL is the core `LBURLOpenPolicy` decision's parsed URL — the
    /// same value the scheme / host gate judged (`rb-url-exit-policy-gate`).
    var externalLiveWatchURL: URL? {
        ExternalLive.externalLiveDecision(liveurl)?.url
    }
}

// MARK: - External-aware tap routing

/// Wraps a host-wired `onTapVideo` into an external-aware closure: when the tapped
/// live is an external-platform broadcast, open its `liveurl` externally (default
/// `UIApplication.open` → installed Facebook app / Safari) and do NOT invoke
/// `onTapVideo` (so no in-app player is presented); otherwise forward to
/// `onTapVideo` unchanged. `open` is injectable so the routing is unit-testable
/// without launching anything (internal-testability).
func externalLiveAwareTap(
    _ onTapVideo: ((LBVideoItem) -> Void)?,
    open: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
) -> (LBVideoItem) -> Void {
    return { item in
        if let url = item.externalLiveWatchURL {
            open(url)
        } else {
            onTapVideo?(item)
        }
    }
}
