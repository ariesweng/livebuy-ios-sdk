import SwiftUI
import UIKit

// MARK: - ProductRowNameTagInlineText — inline name-tag pill + product name via `Text(Image:)`
//         concatenation (rb-ios-product-row-name-tag-wrap-fix, design R39 wrap-fix)
//
// Spec: `goods-status-label-render/spec.md` § "iOS 商品列名稱前「直播價」膠囊" — 「換行後第二行
//        不受標籤欄寬度侷限」Scenario.
// Design: `rb-ios-product-row-name-tag-wrap-fix` design.md (checkpoint-corrected D1/D4).
//
// `ProductRowView`'s `.row` layout used to render the name-prefix tag (`nameTagView`) as a
// FLEX-ROW sibling of `Text(product.name)` inside an `HStack(alignment: .firstTextBaseline,
// spacing: 4)`. `HStack` fixes the name `Text`'s available width to a single value (row width
// minus the pill's width) for its ENTIRE two-line block — a wrapped second line that has
// nothing to its left still got squeezed into that narrow column.
//
// CHECKPOINT CORRECTION: the first implementation of this fix bridged to UIKit
// (`NSTextAttachment` + `UILabel`, hosted via `UIViewRepresentable`) — the nearest analogue to
// Android's `InlineTextContent` / Flutter's `WidgetSpan` / React Native's `<View>`-in-`<Text>`.
// Running this repo's ACTUAL snapshot tests immediately surfaced a showstopper:
// `ReferenceUISnapshotHelper.render`'s iOS-17+ path uses SwiftUI's `ImageRenderer`, which
// cannot flatten `UIViewRepresentable` content in this headless (no real window) test process —
// confirmed by the runtime log `[Invalid Configuration] Unable to render flattened version of
// PlatformViewRepresentableAdaptor<...>` on every affected row, and by the affected PNGs
// shrinking (missing content) rather than merely shifting pixels. That approach was discarded
// entirely in favor of this file: SwiftUI's OWN `Text(Image:)` embedding + `Text` concatenation
// (`+`) achieves the IDENTICAL "inline glyph participates in paragraph wrap" effect using only
// pure-SwiftUI primitives (`Text(Image:)` has existed since iOS 14), which `ImageRenderer`
// renders correctly because there is no `UIViewRepresentable` anywhere in the tree. A
// concatenated `Text` is laid out by SwiftUI/CoreText as ONE paragraph — a wrapped line
// reclaims the row's full available width, exactly like the CSS inline-formatting-context
// behavior the design source (`design/templates/minimal/sdk-components.jsx:LBPProductRow`)
// already has.
enum ProductRowNameTagInlineText {

    /// Fallback (pre-iOS-17) pill appearance. Mirrors the SAME (text, textColor, fillColor,
    /// borderColor, fontSize) tuple `ProductRowView.nameTagView`'s switch derives, so there is
    /// only ever one place (the caller) that decides these values.
    struct PillFallbackSpec {
        let text: String
        let textColor: UIColor
        let fillColor: UIColor
        let borderColor: UIColor?
        let fontSize: CGFloat
    }

    /// 4pt gap between the pill and the name — a SEPARATE, fully-transparent image (design.md
    /// D3), not a literal space character (font-fallback-dependent glyph width).
    static let pillTrailingGap: CGFloat = 4

    /// Fixed (not `UIScreen.main.scale`) so the rasterized pill's resolution is deterministic
    /// across whatever simulator/device runs the test — mirrors
    /// `ReferenceUISnapshotHelper.render`'s own "A fixed scale keeps the baseline
    /// device-independent" rationale.
    private static let pillImageScale: CGFloat = 3

    /// Builds ONE `Text` value: the rasterized pill, a deterministic transparent spacer, then
    /// the plain product name — as `Text(Image:)` / `Text(String:)` fragments concatenated via
    /// `+`. Callers apply `.font` / `.foregroundColor` / `.lineLimit` / `.multilineTextAlignment`
    /// to the RESULT, exactly as the byte-identical `nameTag == .none` branch already does to a
    /// bare `Text(product.name)` — the pill/spacer images are marked `.alwaysOriginal` (both at
    /// the `UIImage` and the SwiftUI `Image` level) so an outer `.foregroundColor` does not tint
    /// them like a template icon.
    ///
    /// `nameFont` (`rb-ios-product-row-name-tag-vertical-align-fix`) MUST be the exact `UIFont`
    /// the caller also applies via `.font(Font(nameFont))` to the returned `Text` — see
    /// `productRowNameTagVerticalOffset`'s doc for why the pill needs this to compute its
    /// vertical-alignment compensation.
    static func build(
        name: String, pillView: AnyView, pillFallback: PillFallbackSpec, nameFont: UIFont
    ) -> Text {
        let pillImage = renderPillImage(pillView: pillView, fallback: pillFallback)
        let spacerImage = renderSpacerImage()
        let verticalOffset = productRowNameTagVerticalOffset(pillHeight: pillImage.size.height, nameFont: nameFont)
        return Text(Image(uiImage: pillImage.withRenderingMode(.alwaysOriginal)).renderingMode(.original))
            .baselineOffset(verticalOffset)
            + Text(Image(uiImage: spacerImage.withRenderingMode(.alwaysOriginal)).renderingMode(.original))
            + Text(name)
    }

    // MARK: - Vertical alignment (design.md D1/D2, `rb-ios-product-row-name-tag-vertical-align-fix`)

    /// The `.baselineOffset` needed to visually center the pill image against `nameFont`'s own
    /// text, instead of the unbalanced default `Text(Image:)` placement.
    ///
    /// Empirically confirmed (design.md D3, throwaway diagnostic render + pixel scan, since public
    /// API docs make no guarantee either way): SwiftUI's `Text(Image:)` embeds an image with its
    /// BOTTOM edge pinned to the surrounding text's baseline, extending the image's full height
    /// upward from there — the same convention as a plain CoreText/`NSTextAttachment` inline
    /// attachment. Left uncompensated, a pill whose own height approaches or exceeds `nameFont`'s
    /// line metrics (the 4 name-tag variants' 11pt text + 1pt vertical padding routinely does)
    /// sits well above where the adjacent text visually centers — looking taller than the name
    /// text and floating above it, exactly the defect this change fixes.
    ///
    /// This moves the pill's default visual center (`pillHeight / 2` above the baseline) to
    /// `nameFont`'s own visual center between its ascender and descender — the same target
    /// Android's `PlaceholderVerticalAlign.TextCenter` and Flutter's `PlaceholderAlignment.middle`
    /// already reach natively. Zero SwiftUI / view dependency by design (`docs/unit-test-
    /// discipline.md`'s "純函式抽出"), so it is unit-testable against plain `UIFont` fixtures
    /// without rendering anything.
    static func productRowNameTagVerticalOffset(pillHeight: CGFloat, nameFont: UIFont) -> CGFloat {
        let nameFontCenterAboveBaseline = (nameFont.ascender - abs(nameFont.descender)) / 2
        let pillDefaultCenterAboveBaseline = pillHeight / 2
        return nameFontCenterAboveBaseline - pillDefaultCenterAboveBaseline
    }

    // MARK: - Pill rasterization

    private static func renderPillImage(pillView: AnyView, fallback: PillFallbackSpec) -> UIImage {
        if #available(iOS 17.0, *) {
            // `ImageRenderer` is `@MainActor`-isolated; `build(...)` always runs on the main
            // thread (it's called from `ProductRowView.body`, itself always evaluated on the
            // main thread) but is not itself declared `@MainActor` at this package's Swift
            // concurrency checking level, so `assumeIsolated` documents that invariant
            // explicitly — mirrors `ReferenceUISnapshotHelper.render`'s identical use (which
            // notes `assumeIsolated` itself needs iOS 17, matching this gate).
            let rendered: UIImage? = MainActor.assumeIsolated {
                let renderer = ImageRenderer(content: pillView.environment(\.colorScheme, .light))
                renderer.scale = pillImageScale
                renderer.isOpaque = false
                return renderer.uiImage
            }
            if let rendered {
                return rendered
            }
        }
        return renderFallbackPillImage(fallback)
    }

    /// Hand-drawn UIKit equivalent of `ProductRowView.nameTagPill` — same padding (4pt
    /// horizontal, 1pt vertical), corner radius (3pt), optional 1pt border. Never exercised by
    /// this repo's test environment (no iOS < 17 simulator runtime is installed — see
    /// `design.md`'s disclosed risk); kept so the package stays genuinely `.iOS(.v14)`-safe at
    /// both compile time and runtime, not just compile time.
    private static func renderFallbackPillImage(_ spec: PillFallbackSpec) -> UIImage {
        let font = UIFont.systemFont(ofSize: spec.fontSize, weight: .medium)
        let horizontalPadding: CGFloat = 4
        let verticalPadding: CGFloat = 1
        let borderWidth: CGFloat = spec.borderColor == nil ? 0 : 1
        let text = spec.text.isEmpty ? " " : spec.text
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let contentSize = CGSize(
            width: max(1, ceil(textSize.width) + horizontalPadding * 2 + borderWidth * 2),
            height: max(1, ceil(textSize.height) + verticalPadding * 2 + borderWidth * 2))

        let format = UIGraphicsImageRendererFormat()
        format.scale = pillImageScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: contentSize, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: contentSize)
                .insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)
            spec.fillColor.setFill()
            path.fill()
            if let borderColor = spec.borderColor {
                borderColor.setStroke()
                path.lineWidth = borderWidth
                path.stroke()
            }
            let textRect = CGRect(
                x: horizontalPadding + borderWidth, y: verticalPadding + borderWidth,
                width: textSize.width, height: textSize.height)
            (text as NSString).draw(
                in: textRect, withAttributes: [.font: font, .foregroundColor: spec.textColor])
        }
    }

    /// A fully-transparent, deterministic `pillTrailingGap`×1pt image — reserves an exact,
    /// font-independent horizontal gap between the pill and the name. NOT a literal space
    /// character (glyph width varies by font/fallback — the exact regression Android's sibling
    /// change hit in its first round, `archive/2026-09-15-rb-android-product-row-name-tag-wrap-
    /// fix/tasks.md` §7.1).
    private static func renderSpacerImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = pillImageScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pillTrailingGap, height: 1), format: format)
        return renderer.image { _ in }
    }
}
