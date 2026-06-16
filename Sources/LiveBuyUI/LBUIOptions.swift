import LiveBuySDK

/// Host-level UI preferences passed to `LiveBuyUI.install(options:)`.
/// All fields are optional; nil means "defer to template default".
/// sdkConfig values always win over these options (Layer 3 > Layer 2 in the merge).
///
/// Spec: `ui-template-foundation/spec.md` § "LiveBuyUI 入口 API"
public struct LBUIOptions {

    /// Per-element show/hide overrides.  nil per-field = defer to template default.
    public var visibility: SDKConfig.Visibility?

    /// Brand color + font scale preferences.
    public var theme: SDKConfig.Theme?

    /// Player-specific layout preferences (arbitrary key-value map).
    /// Well-known keys are defined by each template (e.g. `"productOverlay_position"`).
    public var layoutPlayer: [String: Any]?

    /// Widget-specific layout preferences (arbitrary key-value map).
    public var layoutWidget: [String: Any]?

    public init(
        visibility: SDKConfig.Visibility? = nil,
        theme: SDKConfig.Theme? = nil,
        layoutPlayer: [String: Any]? = nil,
        layoutWidget: [String: Any]? = nil
    ) {
        self.visibility = visibility
        self.theme = theme
        self.layoutPlayer = layoutPlayer
        self.layoutWidget = layoutWidget
    }
}
