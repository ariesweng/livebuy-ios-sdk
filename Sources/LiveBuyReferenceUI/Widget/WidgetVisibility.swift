import Foundation
import LivebuySDK

// MARK: - Widget video visibility (rb-ios-widget-hide-urlless-live)
//
// Spec: `widget-hide-urlless-live/spec.md`.
//
// `/sdk/widget` occasionally returns a live whose `type == 2` (直播) and
// `liveStatus == 1` (直播中) but whose `liveurl` is empty ("") — a live with NO
// playable stream URL on the widget layer. No SDK playback engine can play it, so
// the reference-ui drop-in HIDES it (carousel / grid card list + floating preview)
// rather than render a dead card.
//
// This rule keys ONLY on an EMPTY `liveurl`: any live carrying a non-empty
// `liveurl` (whatever the host) is NEVER hidden here and surfaces normally —
// only the EMPTY-`liveurl` live is hidden.
//
// The predicate is a PURE, POSITIVE three-condition AND — NEVER a negative rule
// such as "the `liveurl` is not `.m3u8`": the backend may legitimately return a
// non-`.m3u8` MP4/VOD `liveurl` for a normal in-app video (per
// `widget-live-nested-decode`), so a negative rule would misclassify those.

enum WidgetVisibility {

    /// Whether `video` is an **in-app-unplayable live** — a live (`type == 2`) that
    /// is currently live (`liveStatus == 1`) but carries NO playable stream URL on
    /// the widget layer (`liveurl == ""`). PURE — unit-testable in isolation; returns
    /// `false` the moment ANY one of the three conditions is false.
    static func isUrllessLive(_ video: LBVideoItem) -> Bool {
        video.type == 2 && video.liveStatus == 1 && video.liveurl.isEmpty
    }

    /// The card-row data with every `isUrllessLive` video removed, preserving the
    /// relative order of the remaining (displayed) videos. Non-matching videos are
    /// untouched.
    static func visibleVideos(_ videos: [LBVideoItem]) -> [LBVideoItem] {
        videos.filter { !isUrllessLive($0) }
    }

    /// The floating live card, or `nil` when it is an `isUrllessLive` live (so the
    /// floating surface renders nothing and the minimized pill reports not-live). A
    /// normal live — or a `nil` input — passes through unchanged.
    static func visibleLive(_ video: LBVideoItem?) -> LBVideoItem? {
        if let video, isUrllessLive(video) { return nil }
        return video
    }
}
