import Foundation
import UIKit
import LiveBuySDK

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
    static func isExternalLiveURL(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return hosts.contains { base in host == base || host.hasSuffix("." + base) }
    }
}

public extension LBVideoItem {

    /// The external-platform watch URL when this live's `liveurl` is an external
    /// broadcast (Facebook today), else `nil`. Tapping such a live opens this URL
    /// externally instead of the in-app player.
    var externalLiveWatchURL: URL? {
        guard ExternalLive.isExternalLiveURL(liveurl) else { return nil }
        return URL(string: liveurl)
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
