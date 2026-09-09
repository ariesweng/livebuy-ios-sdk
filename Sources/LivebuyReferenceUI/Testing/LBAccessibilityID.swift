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

    /// Central paused-overlay mute-toggle button (44px, `PlaybackPausedOverlayView`,
    /// rb-ios-gesture-clean-mode-rewrite — takes over from the retired
    /// `GesturePauseIconView`). RETIRED (`rb-ios-gesture-clean-mode-v2`) — the overlay is
    /// no longer composed by `PlayerShellView`; id kept (not removed) for the same reason
    /// `PlaybackPausedOverlayView.swift` itself is kept, see that file's header comment.
    public static let pausedOverlayMuteButton = "lb_paused_overlay_mute_button"
    /// Central paused-overlay resume button (64px, `PlaybackPausedOverlayView`). RETIRED
    /// (`rb-ios-gesture-clean-mode-v2`) — see `pausedOverlayMuteButton` above.
    public static let pausedOverlayResumeButton = "lb_paused_overlay_resume_button"

    /// Clean-mode-only mute-toggle button in `PlayerHeaderBarView`'s `iconCluster`
    /// (`rb-ios-gesture-clean-mode-v2`, design R29) — restores the mute affordance the
    /// retired single-tap-on-video-area gesture used to carry.
    public static let playerHeaderMuteButton = "lb_player_header_mute_button"
    ///「退出乾淨模式」small round button, shown only while `cleanMode == true`
    /// (`rb-ios-gesture-clean-mode-v2`, design R29).
    public static let cleanModeExitButton = "lb_clean_mode_exit_button"

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
    ///「更多」(⋯) button — chatClosed-only leading slot (nickname's position), opens
    /// `LiveMoreSheetView` (rb-ios-live-replay-more-menu-and-video-info-live-copy, design R32).
    public static let liveMore = "lb_live_more"
    /// 字幕 (CC) toggle button — chatClosed-only trailing slot (share's old position),
    /// forwards `onToggleCC` (rb-ios-live-replay-more-menu-and-video-info-live-copy 補正輪,
    /// restoring the pre-`prerecorded-live-bottom-bar-comment` CC button at its new R32
    /// position). `lb_rail_subtitle`'s sibling for the LIVE bottom bar surface.
    public static let liveCC = "lb_live_cc"

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

    /// VOD / replay playback-progress transport bar (rb-ios-restore-vod-playback-progress-bar).
    public static let playbackProgressBar = "lb_playback_progress_bar"
    /// The expanded transport bar's play/pause button.
    public static let playbackProgressPlayPause = "lb_playback_progress_play_pause"
    /// The draggable seek track (idle thin line + expanded handle track share this id).
    public static let playbackProgressTrack = "lb_playback_progress_track"
    /// The drag-time centered `HH:MM:SS / HH:MM:SS` timestamp readout.
    public static let playbackProgressReadout = "lb_playback_progress_readout"

    /// The right-edge「現正直播」半藥丸鈕 (rb-ios-live-now-pill, `LBLiveNowPill`).
    public static let liveNowPill = "lb_live_now_pill"

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

    // LIVE bottom bar「更多」(⋯) collapsible sheet (`LiveMoreSheetView`,
    // rb-ios-live-replay-more-menu-and-video-info-live-copy, design R32).
    public static let liveMoreSheet = "lb_live_more_sheet"
    public static let liveMoreShare = "lb_live_more_share"
    public static let liveMoreContact = "lb_live_more_contact"

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

    /// 活動參加入口（`WinEntryView(variant: .activity)`，rb-ios-live-activity-sheet）。
    /// 獨立於 `winEntry`——兩顆浮動入口可能同時出現在畫面上，E2E 需能分辨。
    public static let activityEntry = "lb_activity_entry"

    public static let winClaimSheet = "lb_win_claim_sheet"
    public static let winClaimPrimary = "lb_win_claim_primary"
    public static let winClaimResultBanner = "lb_win_claim_result_banner"
    public static let winClaimScrim = "lb_win_claim_scrim"

    // 四階段領獎流程（rb-ios-win-claim-email-flow）。
    /// claim 階段的 email 輸入欄（runtime `TextField` / snapshot 靜態佔位共用同一 id）。
    public static let winClaimEmailField = "lb_win_claim_email_field"
    /// `confirmSubmit` 的 alert 卡（`confirmClose` 已隨 R27 退役）。
    public static let winClaimAlert = "lb_win_claim_alert"
    /// 分頁圓點列（`rb-ios-win-claim-pagination`，R27）——只在 `claim` 卡、`pageCount > 1`
    /// 時出現。
    public static let winClaimPaginationDots = "lb_win_claim_pagination_dots"
    /// alert 的「確定」。
    public static let winClaimAlertConfirm = "lb_win_claim_alert_confirm"
    /// alert 的「取消」。
    public static let winClaimAlertCancel = "lb_win_claim_alert_cancel"
    /// 送出中疊層（scrim + spinner +「送出中…」）。
    public static let winClaimSubmitting = "lb_win_claim_submitting"
    /// `done`（discount）的折扣碼「複製」鈕。
    public static let winClaimCopyCode = "lb_win_claim_copy_code"
    /// `fail` 卡的通用錯誤提示列（**不含**任何錯誤代碼，見 R13 刻意分歧 2/2）。
    public static let winClaimFailNotice = "lb_win_claim_fail_notice"
    /// 卡底 footer「使用條款 | 隱私政策」外層共用 id（兩段文字各自的 id 見下）。
    public static let winClaimFooter = "lb_win_claim_footer"
    /// footer「使用條款」文字（rb-ios-win-claim-footer-links，可點擊）。
    public static let winClaimFooterTerms = "lb_win_claim_footer_terms"
    /// footer「隱私政策」文字（rb-ios-win-claim-footer-links，可點擊）。
    public static let winClaimFooterPrivacy = "lb_win_claim_footer_privacy"

    // 抽獎活動參加彈窗（`LiveActivitySheetView`，rb-ios-live-activity-sheet）。單階段呈現
    // （design.md D3），不覆用上面的 `winClaim*` 系列 id（D5）。
    /// modal-root（置中卡）。
    public static let activitySheet = "lb_activity_sheet"
    /// 外層 scrim（點擊即關閉——`LBActivitySheet` 無 stage 門檻，恆可點擊關閉）。
    public static let activitySheetScrim = "lb_activity_sheet_scrim"
    /// 「立即參加」CTA（恆可重複點擊，不鎖定——`rb-ios-activity-sheet-cta-repeatable`）。
    public static let activitySheetCta = "lb_activity_sheet_cta"
    /// 分頁圓點列（`activity-sheet-pagination-reference-ui-ios`）——只在 `pageCount > 1`
    /// 時出現。獨立於 `winClaimPaginationDots`（兩個彈窗是不同螢幕物件，共用 id 會讓 E2E
    /// 無法區分究竟是哪個彈窗的分頁圓點）。
    public static let activitySheetPaginationDots = "lb_activity_sheet_pagination_dots"

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
    /// Header close button while it reads as「返回」(non-empty `detailBreadcrumb`,
    /// rb-ios-product-detail-recommendations §5). Distinct id from `sheetHeaderClose` so
    /// E2E can assert which affordance is currently drawn.
    public static let sheetHeaderBack = "lb_sheet_header_back"
    public static let productDetail = "lb_product_detail"

    /// 商品明細「商品介紹」文字區 (rb-ios-product-detail-recommendations §2).
    public static let productIntro = "lb_product_intro"
    /// 商品明細「更多商品」推薦格容器 (rb-ios-product-detail-recommendations §3).
    public static let productRecommendations = "lb_product_recommendations"
    public static func productRecommendationCard(_ index: Int) -> String { "lb_product_recommendation_card_\(index)" }
    public static func productRecommendationPlay(_ index: Int) -> String { "lb_product_recommendation_play_\(index)" }
    public static func productRecommendationCart(_ index: Int) -> String { "lb_product_recommendation_cart_\(index)" }
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

    /// Sale badge chip on the product-detail / add-to-cart sheet (rb-ios-product-sale-badge).
    public static let saleBadge = "lb_sale_badge"

    public static let zoomBadge = "lb_zoom_badge"
    public static let zoomOverlay = "lb_zoom_overlay"
    public static let imageZoomImage = "lb_image_zoom_image"
    public static let zoomClose = "lb_zoom_close"

    /// 商品明細主圖相簿的縮圖選取列（`rb-ios-product-detail-image-gallery`，design R34）——
    /// 一個 index 一顆，`tap` 跳圖。
    public static func productGalleryThumbnail(_ index: Int) -> String { "lb_product_gallery_thumbnail_\(index)" }

    /// 商品明細主圖相簿的大圖手勢面容器（`rb-ios-product-photo-gallery-scroll-conflict`）——
    /// 供 E2E 定位真實觸控拖曳的起點（大圖區域），比照 Android `PRODUCT_DETAIL_PHOTO_GALLERY`
    /// testTag 的做法。
    public static let productGalleryMainImage = "lb_product_gallery_main_image"

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
    // NOTE: `momentEndReshuffle` / `momentEndHotRow` / `momentHotCard(_:)` (the retired 熱門
    // variant's「換一批」pill / card row / per-card ids) were removed
    // (`rb-ios-endscreen-live-empty-state`) — EndScreen's non-countdown branch is now the
    // 空狀態變體, which has no per-item list. See `momentEndViewCart` below.
    public static let momentEndViewCart = "lb_moment_end_view_cart"
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
    public static let cardUpcomingOverlay = "lb_card_upcoming_overlay"
    /// Top-right「置頂」pin badge (`item.pin == 1`, rb-ios-carousel-card-pin-viewers-
    /// duration-removal, design R33). Independent of `cardKindBadge`.
    public static let cardPinnedBadge = "lb_card_pinned_badge"
    /// LIVE-only viewer-count pill beside `cardLiveBadge` (`item.watchNum`, gated by
    /// `item.showPvNum == 1`, rb-ios-carousel-card-pin-viewers-duration-removal,
    /// design R33).
    public static let cardViewerCountBadge = "lb_card_viewer_count_badge"

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
    /// Inline「暱稱被取走 / 設定失敗」error row (rb-ios-nickname-taken-inline-error).
    public static let guestNameError = "lb_guest_name_error"

    // MARK: - Family 7 — container + sheetkit

    public static let bottomSheetScrim = "lb_bottom_sheet_scrim"
    public static let chatComposer = "lb_chat_composer"
    public static let chatSend = "lb_chat_send"
    public static let chatComposerDismiss = "lb_chat_composer_dismiss"
    // NOTE: no `lb_collapsed_floating_card` — iOS has no collapsible floating-card
    // surface; the minimized widget pill is `minimizedWidget` (Family 5).
}
