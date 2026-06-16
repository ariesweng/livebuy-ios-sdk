import LiveBuySDK

/// Entry point for the optional UI template layer.
/// Call `install(template:options:)` once (before or after `LiveBuySDK.configure()`)
/// to enable a built-in UI template.  The merge of template defaults, host options,
/// and sdkConfig is deferred to Widget / Player instantiate time.
///
/// Spec: `ui-template-foundation/spec.md` § "LiveBuyUI 入口 API"
public final class LiveBuyUI {

    private static var _installedTemplate: AnyLBTemplate?
    private static var _hostOptions: LBUIOptions?

    private init() {}

    // MARK: - Public API

    /// Install a template.  Idempotent — repeated calls replace the previous registration.
    ///
    /// Registers the core's template-agnostic `onInstantiate` hooks
    /// (`LiveBuyPlayerViewController` / `LiveBuyWidgetCore`) so that every Player /
    /// Widget instantiated after this call gets the matching Default template
    /// handler attached and its SDK events wired (two routes — see
    /// `TemplateAttachment.swift`).  The hook closures hold only install-level
    /// state and weak-capture the instance, so they never retain any instance
    /// (architectural invariant: dependency is one-way UI → Core, and no leak).
    ///
    /// - Parameters:
    ///   - template: The template to activate (e.g. `DefaultTemplate()`).
    ///   - options:  Host-level config preferences. May be overridden by `sdkConfig`.
    public static func install(template: AnyLBTemplate = DefaultTemplate(),
                               options: LBUIOptions? = nil) {
        _installedTemplate = template
        _hostOptions = options
        // Wire the core instantiation hooks → attach at instantiate time.
        LiveBuyPlayerViewController.onInstantiate = { vc in
            TemplateWiring.attachPlayer(vc)
        }
        LiveBuyWidgetCore.onInstantiate = { widget in
            TemplateWiring.attachWidget(widget)
        }
    }

    /// Remove the installed template.  Clears the core hooks so subsequent
    /// Widget / Player instantiations run headless (SDK default behaviour).
    /// Already-attached instances keep their attachment until they dealloc
    /// (no forced mid-session teardown — design D5).
    public static func uninstall() {
        _installedTemplate = nil
        _hostOptions = nil
        LiveBuyPlayerViewController.onInstantiate = nil
        LiveBuyWidgetCore.onInstantiate = nil
    }

    /// Whether a template is currently installed.
    public static var isInstalled: Bool { _installedTemplate != nil }

    /// The Default Player template instance attached to `player`, if any.
    ///
    /// Use this to bind the host UI to the template's host-bindable state:
    /// the merged `activityFeed.items`, the unclaimed `winClaim.unclaimedCount`
    /// / `winClaim.unclaimedWinners`, and the `winClaim.resultState`; register
    /// `template.onChange` to be notified (main thread) whenever any of that
    /// state changes and re-read it.
    ///
    /// Returns `nil` — and never throws — when no Default template is installed
    /// or `player` has not yet been attached (e.g. before `loadView`). The host
    /// consumes the returned instance's read surface; it does NOT construct the
    /// instance or feed events into it (those entry points stay internal).
    ///
    /// Spec: `ui-template-foundation/spec.md`
    ///   § "Default Template Host 取得實例介面（per-player accessor）"
    ///
    /// - Parameter player: the Player to look up the attached template for.
    /// - Returns: the attached `DefaultPlayerTemplate`, or `nil`.
    public static func playerTemplate(for player: LiveBuyPlayerViewController) -> DefaultPlayerTemplate? {
        TemplateAttachment.bound(to: player)?.playerTemplate
    }

    /// The Default Widget template instance attached to `widget`, if any.
    ///
    /// Symmetric with `playerTemplate(for:)`. Use this to bind the host UI to the
    /// widget's host-bindable content view-model — `template.content.current`
    /// (`videos` / `mode` / `currentPage` / `lastPage` / `liveVideo` /
    /// `widgetColor` / `widgetBgcolor`) — so a host / reference-ui can draw
    /// `widgets.jsx` (`LBPCarousel` / `LBPVideoShop` / `LBPFloatingWidget` /
    /// `LBPMinimizedWidget`). Register `template.onChange` to be notified (main
    /// thread) whenever the widget content changes and re-read it.
    ///
    /// Returns `nil` — and never throws — when no Default template is installed or
    /// `widget` has not yet been attached (e.g. before instantiation). The host
    /// consumes the returned instance's read surface; it does NOT construct the
    /// instance or feed data into it (those entry points stay internal).
    ///
    /// Spec: `ui-template-foundation/spec.md`
    ///   § "Default Template Host 取得 widget template 實例介面"
    ///
    /// - Parameter widget: the Widget to look up the attached template for.
    /// - Returns: the attached `DefaultWidgetTemplate`, or `nil`.
    public static func widgetTemplate(for widget: LiveBuyWidgetCore) -> DefaultWidgetTemplate? {
        TemplateAttachment.bound(to: widget)?.widgetTemplate
    }

    // MARK: - Internal access (for template layer use only)

    static var installedTemplate: AnyLBTemplate? { _installedTemplate }
    static var hostOptions: LBUIOptions? { _hostOptions }
}
