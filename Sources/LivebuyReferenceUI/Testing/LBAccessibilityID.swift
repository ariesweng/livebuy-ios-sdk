import Foundation

/// Central registry of E2E `accessibilityIdentifier` strings for `LivebuyReferenceUI`.
///
/// This is the ONLY legal home for E2E id string literals. Production reference-ui
/// components MUST reference `LBAccessibilityID.<name>` (or a per-item helper) and
/// MUST NOT hardcode `.accessibilityIdentifier("...")` literals — enforced by
/// `scripts/check-a11y-id-literals.sh`.
///
/// String VALUES mirror the Android `LBTestTags` registry 1:1 (`lb_` prefix,
/// snake_case, `..._{index}` per-item form) so the same E2E scenario id names carry
/// across platforms. Swift constant names are camelCase; the values are the shared
/// snake_case tokens.
///
/// `public` so the QA gallery host (Example app) and the XCUITest target can address
/// elements via these constants instead of magic strings.
public enum LBAccessibilityID {

    // MARK: - Family 1 — player-shell + chrome

    public static let playerShell = "lb_player_shell"
    public static let playerVideoSurface = "lb_player_video_surface"
    public static let playerHeader = "lb_player_header"
    public static let playerHeaderHostPill = "lb_player_header_host_pill"
    public static let subscribeBadge = "lb_subscribe_badge"
    public static let playerMinimize = "lb_player_minimize"

    public static let operationRail = "lb_operation_rail"
    public static let railLike = "lb_rail_like"
    public static let railComment = "lb_rail_comment"
    public static let railShare = "lb_rail_share"
    public static let railSubtitle = "lb_rail_subtitle"
    public static let railService = "lb_rail_service"
    public static let railGoods = "lb_rail_goods"

    public static let liveBagButton = "lb_live_bag_button"
    public static let liveCommentPill = "lb_live_comment_pill"
    public static let livePersonEdit = "lb_live_person_edit"
    public static let liveShare = "lb_live_share"
    public static let liveHeart = "lb_live_heart"

    public static let announceBanner = "lb_announce_banner"
    public static let pinnedCard = "lb_pinned_card"
    /// Pinned-card close chip (top-right X) — per-product-id local dismiss
    /// (rb-ios-live-pinned-card-dismiss). Value mirrors Android
    /// `LBTestTags.PINNED_CARD_CLOSE`.
    public static let pinnedCardClose = "lb_pinned_card_close"
    public static let pinnedCarousel = "lb_pinned_carousel"
    public static func livePinnedDot(_ index: Int) -> String { "lb_live_pinned_dot_\(index)" }

    public static let nowIntroCarousel = "lb_now_intro_carousel"
    public static let nowIntroducingCard = "lb_now_introducing_card"
    public static func nowIntroducingDot(_ index: Int) -> String { "lb_now_introducing_dot_\(index)" }

    public static let infoPanel = "lb_info_panel"
    public static let infoTabDetail = "lb_info_tab_detail"
    public static let infoTabNotice = "lb_info_tab_notice"
    public static let infoPanelHome = "lb_info_panel_home"
    public static let infoFooterContact = "lb_info_footer_contact"
    // NOTE: the video info panel is presented via the shared SheetKit
    // `BottomSheetPresenter`, so its scrim IS `bottomSheetScrim` (Family 7) — there
    // is no self-drawn `lb_info_panel_scrim`. Bottom-sheet-presented surfaces are
    // mutually exclusive, so the shared scrim id is unambiguous at assert time.

    public static let contactModal = "lb_contact_modal"
    public static let contactCancel = "lb_contact_cancel"
    public static let contactConfirm = "lb_contact_confirm"
    public static let contactScrim = "lb_contact_scrim"

    public static let momentCountdownRoot = "lb_moment_countdown_root"

    // MARK: - Family 2 — feed + win

    public static let chatFeed = "lb_chat_feed"
    public static func chatLine(_ index: Int) -> String { "lb_chat_line_\(index)" }
    public static func activityLine(_ index: Int) -> String { "lb_activity_line_\(index)" }
    public static let eventJoinCta = "lb_event_join_cta"
    public static let eventJoinJoined = "lb_event_join_joined"
    public static let pinnedBanner = "lb_pinned_banner"
    public static let chatScrollToBottom = "lb_chat_scroll_to_bottom"
    /// Activity-notification toast above the chat feed (`ActivityToastView`,
    /// rb-ios-activity-toast).
    public static let activityToast = "lb_activity_toast"

    public static let winEntry = "lb_win_entry"
    public static let winClaimSheet = "lb_win_claim_sheet"
    public static let winClaimPrimary = "lb_win_claim_primary"
    public static let winClaimSecondary = "lb_win_claim_secondary"
    public static let winClaimClose = "lb_win_claim_close"
    public static let winClaimResultBanner = "lb_win_claim_result_banner"
    public static let winClaimScrim = "lb_win_claim_scrim"

    // MARK: - Family 3 — product + sheets

    public static let productList = "lb_product_list"
    public static let playerBag = "lb_player_bag"
    public static let sheetSearchField = "lb_sheet_search_field"
    public static let sheetSearchClear = "lb_sheet_search_clear"
    public static let sheetSearchCancel = "lb_sheet_search_cancel"
    public static let productSearchButton = "lb_product_search_button"
    public static let cartCtaFooter = "lb_cart_cta_footer"

    public static func productRowThumb(_ index: Int) -> String { "lb_product_row_thumb_\(index)" }
    public static func productRowDetail(_ index: Int) -> String { "lb_product_row_detail_\(index)" }
    public static func productRowShare(_ index: Int) -> String { "lb_product_row_share_\(index)" }
    public static func productRowCart(_ index: Int) -> String { "lb_product_row_cart_\(index)" }

    public static let sheetHeaderClose = "lb_sheet_header_close"
    public static let productDetail = "lb_product_detail"
    public static func variantChip(_ group: Int, _ option: Int) -> String { "lb_variant_chip_\(group)_\(option)" }
    public static let qtyPlus = "lb_qty_plus"
    public static let qtyMinus = "lb_qty_minus"
    public static let favButton = "lb_fav_button"
    public static let shareButton = "lb_share_button"
    public static let variantPrompt = "lb_variant_prompt"

    public static let addToCartSheet = "lb_add_to_cart_sheet"
    public static let addToCartCta = "lb_add_to_cart_cta"
    public static let addToCartRetry = "lb_add_to_cart_retry"
    /// Add-to-cart success toast (`CartToastView`, rb-ios-cart-add-success-toast).
    public static let cartToast = "lb_cart_toast"

    public static let zoomBadge = "lb_zoom_badge"
    public static let zoomOverlay = "lb_zoom_overlay"
    public static let imageZoomImage = "lb_image_zoom_image"
    public static let zoomClose = "lb_zoom_close"

    public static let notifyRestockSheet = "lb_notify_restock_sheet"
    public static let restockNoticeCta = "lb_restock_notice_cta"

    // NOTE: the mini-cart peek surface was removed from production
    // (`rb-ios-remove-minicart-peek-surface`); `MiniCartView` now renders only as
    // the VOD now-introducing card, addressed via `nowIntroducingCard` at its call
    // site. No `lb_minicart_peek` / `_close` ids until a peek surface returns.

    // MARK: - Family 4 — moments

    public static let momentRoot = "lb_moment_root"
    public static let momentError = "lb_moment_error"
    public static let momentErrorRetry = "lb_moment_error_retry"
    public static let momentErrorBack = "lb_moment_error_back"
    public static let momentEnd = "lb_moment_end"
    public static let momentEndWatch = "lb_moment_end_watch"
    public static let momentEndCancel = "lb_moment_end_cancel"
    public static let momentEndReshuffle = "lb_moment_end_reshuffle"
    public static let momentEndHotRow = "lb_moment_end_hot_row"
    public static func momentHotCard(_ index: Int) -> String { "lb_moment_hot_card_\(index)" }
    public static let momentStart = "lb_moment_start"
    public static let momentStartSkip = "lb_moment_start_skip"
    public static let momentLoading = "lb_moment_loading"

    // MARK: - Family 5 — widget

    public static let widgetCarousel = "lb_widget_carousel"
    public static func carouselCard(_ index: Int) -> String { "lb_carousel_card_\(index)" }
    public static let widgetGrid = "lb_widget_grid"
    public static func gridCard(_ index: Int) -> String { "lb_grid_card_\(index)" }
    public static let gridLoadMoreFooter = "lb_grid_load_more_footer"
    public static let gridEndLabel = "lb_grid_end_label"
    public static let widgetSeeMore = "lb_widget_see_more"

    public static let cardKindBadge = "lb_card_kind_badge"
    public static let cardLiveBadge = "lb_card_live_badge"
    public static let cardDurationPill = "lb_card_duration_pill"
    public static let cardUpcomingOverlay = "lb_card_upcoming_overlay"

    public static let floatingWidget = "lb_floating_widget"
    public static let floatingClose = "lb_floating_close"
    public static let minimizedWidget = "lb_minimized_widget"
    public static let minimizedClose = "lb_minimized_close"
    public static let minimizedExpand = "lb_minimized_expand"
    public static let loopingPreview = "lb_looping_preview"

    // MARK: - Family 6 — gap-surfaces

    public static let authGateModal = "lb_auth_gate_modal"
    public static let authGateLogin = "lb_auth_gate_login"
    public static let authGateLater = "lb_auth_gate_later"
    public static let authGateScrim = "lb_auth_gate_scrim"

    public static let guestNameModal = "lb_guest_name_modal"
    public static let guestNameField = "lb_guest_name_field"
    public static let guestNameSubmit = "lb_guest_name_submit"
    public static let guestNameScrim = "lb_guest_name_scrim"

    // MARK: - Family 7 — container + sheetkit

    public static let bottomSheetScrim = "lb_bottom_sheet_scrim"
    public static let chatComposer = "lb_chat_composer"
    public static let chatSend = "lb_chat_send"
    public static let chatComposerDismiss = "lb_chat_composer_dismiss"
    // NOTE: no `lb_collapsed_floating_card` — iOS has no collapsible floating-card
    // surface; the minimized widget pill is `minimizedWidget` (Family 5).
}
