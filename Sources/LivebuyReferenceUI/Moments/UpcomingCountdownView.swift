import SwiftUI
import LivebuyUI

// MARK: - UpcomingCountdownView — moment surface 4 (直播預告等待開播)
//
// Spec: `reference-ui-rendering/spec.md` (Moments family) — Upcoming 等待開播 moment.
// Design: `design/templates/minimal/live-chrome.jsx` `LBLiveUpcomingOverlay`.
//
// Full-bleed「等待開播」moment shown when the player is in `awaitingLive`
// (`live_status == 0`, 直播預告). Aligned to the design's `LBLiveUpcomingOverlay`:
//   • the COVER image as the background (runtime, scaleAspectFill) + a `rgba(0,0,0,0.35)`
//     dark mask (so the text reads); `live == false` / empty cover → solid `theme.background`
//     (snapshot-deterministic, no remote load),
//   • centered「scheduled DATE」(small) +「scheduled TIME」(big) — parsed from the backend
//     `publish_at` by pure string components (timezone-independent + snapshot-stable).
//
// The design has NO「即將開播」label and NO ticking「距開播 HH:MM:SS」countdown — just the
// scheduled date + big time. So there is no Timer / `Date()` dependency → `ImageRenderer`
// baselines stay deterministic.
//
// iOS-14-safe: ZStack / VStack / Text + `RemoteStillImageView`. No Lazy* / ScrollView /
// AsyncImage.

public struct UpcomingCountdownView: View {

    public let theme: ReferenceUITheme
    /// Scheduled start — backend `publish_at` (`"yyyy-MM-dd HH:mm:ss"`, UTC+8).
    public let scheduledStartAt: String
    /// Runtime opt-in. `false` (default — demo / snapshot) → solid background, no remote
    /// cover load (deterministic). `true` (host runtime) → loads the cover background.
    public let live: Bool
    /// The video cover URL (`MomentsModel.upcomingCover` ← `channel.cover`). Rendered as
    /// the full-bleed background on the `live == true` runtime path; empty → solid background.
    public let coverUrl: String

    public init(theme: ReferenceUITheme, scheduledStartAt: String, live: Bool = false, coverUrl: String = "") {
        self.theme = theme
        self.scheduledStartAt = scheduledStartAt
        self.live = live
        self.coverUrl = coverUrl
    }

    public var body: some View {
        ZStack {
            // Background: cover (runtime, fill) + dark mask; else solid theme.background.
            if live, let url = coverURL {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                    .ignoresSafeArea()
                Color.black.opacity(0.35).ignoresSafeArea()
            } else {
                theme.background.ignoresSafeArea()
            }

            // Content (centered): scheduled date (small) + scheduled time (big). White +
            // shadow, mirroring the design's `LBLiveUpcomingOverlay`.
            VStack(spacing: 12) {
                if !Self.scheduledDate(scheduledStartAt).isEmpty {
                    Text(Self.scheduledDate(scheduledStartAt))
                        .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(Self.scheduledTime(scheduledStartAt))
                    .font(.system(size: 56 * theme.fontScale, weight: .heavy).monospacedDigit())
                    .foregroundColor(.white)
            }
            .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 2)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.momentCountdownRoot)
    }

    private var coverURL: URL? {
        let s = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    // MARK: - Pure display helpers (shared with CarouselCardView's upcoming card)

    /// Reformat `publish_at` `"2026-06-11 13:40:00"` → `"6月11日"`（M月D日，去前導 0）by pure
    /// string components (no Date round-trip → timezone-independent + deterministic). Empty /
    /// unexpected shape → "".
    static func scheduledDate(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard let datePart = parts.first?.split(separator: "-"), datePart.count == 3,
              let month = Int(datePart[1]), let day = Int(datePart[2]) else { return "" }
        return "\(month)月\(day)日"
    }

    /// Reformat `publish_at` `"2026-06-11 13:40:00"` → `"13:40"`（HH:MM）by pure string
    /// components. Empty / unexpected shape → "".
    static func scheduledTime(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return "" }
        let time = parts[1].split(separator: ":")
        guard time.count >= 2 else { return "" }
        return "\(time[0]):\(time[1])"
    }

    /// Parse `"yyyy-MM-dd HH:mm:ss"` as UTC+8 (the API timestamp convention). Used by
    /// `CarouselCardView.isUpcoming` to detect a future scheduled start.
    static func parseUTC8(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f.date(from: s)
    }
}

#if DEBUG
struct UpcomingCountdownView_Previews: PreviewProvider {
    static var previews: some View {
        UpcomingCountdownView(theme: ReferenceUIThemePalette.minimal,
                              scheduledStartAt: "2026-06-11 13:40:00")
            .previewLayout(.fixed(width: 320, height: 600))
    }
}
#endif
