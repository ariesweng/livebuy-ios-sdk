import Foundation

/// Single, shared `http://` → `https://` upgrade point for remote IMAGE loads
/// (rb-ios-product-image-https-upgrade).
///
/// Why: some backend product `pic` URLs are cleartext `http://` (e.g. shop `P1MUv99J`'s
/// 測試零食). iOS App Transport Security blocks cleartext loads BEFORE the request is even
/// sent, so `URLSession` (via `RemoteStillImageView`) returns no data → the real product
/// image never appears and the placeholder (gradient / monogram chip) stays. The LiveBuy
/// image host serves the very same path over TLS — it even 301-redirects `http`→`https` —
/// so upgrading the scheme client-side makes the image load. Loading product imagery over
/// cleartext is never desirable anyway.
///
/// Applied centrally at the one fetch chokepoint (`RemoteStillImageView`), so every image
/// call site (product list / detail / mini-cart / live overlay / carousel / shop logo)
/// benefits without per-helper churn. Only the `http` scheme is rewritten — `https`, other
/// schemes, relative paths and empty strings keep their existing behavior (empty → nil).
enum ReferenceUIImageURL {
    /// Build an image `URL` from a raw string: trims whitespace, treats empty as "no image"
    /// (`nil`), and upgrades a cleartext `http://` scheme to `https://`.
    static func make(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s) else { return nil }
        return url.lbHTTPSUpgraded
    }
}

extension URL {
    /// If the scheme is exactly `http` (case-insensitive), return the same URL with an
    /// `https` scheme; otherwise return `self` unchanged (host / path / query preserved).
    var lbHTTPSUpgraded: URL {
        guard scheme?.lowercased() == "http" else { return self }
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false)
        comps?.scheme = "https"
        return comps?.url ?? self
    }
}
