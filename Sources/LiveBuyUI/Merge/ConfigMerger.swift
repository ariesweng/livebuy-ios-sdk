import LiveBuySDK

/// Three-layer config merge for the LiveBuyUI template system.
///
/// Priority (low → high):
///   Layer 1: Template defaults  (written in template source)
///   Layer 2: Host install() options  (LBUIOptions)
///   Layer 3: sdkConfig  (backend — always wins when non-nil)
///
/// `nil` means "hands off" (this layer does not express a preference).
/// `nil` ≠ `false`.
///
/// Merge is executed at Widget / Player instantiate time, not at `install()` time.
/// The result is snapshotted for the instance lifetime (not reactive).
///
/// Spec: `ui-template-config-merge/spec.md`
public struct ConfigMerger {

    // MARK: - Visibility

    /// Produces the effective visibility for a single flag.
    /// - Parameters:
    ///   - sdkValue:       Value from `sdkConfig.visibility.*` (Layer 3).
    ///   - hostValue:      Value from `hostOptions.visibility.*` (Layer 2).
    ///   - templateDefault: Template's built-in default (Layer 1).
    public static func effectiveVisibility(
        sdkValue: Bool?,
        hostValue: Bool?,
        templateDefault: Bool
    ) -> Bool {
        if let v = sdkValue   { return v }
        if let v = hostValue  { return v }
        return templateDefault
    }

    /// Convenience overload that reads from the full `SDKConfig.Visibility` struct.
    public static func effectiveVisibility(
        from sdkConfig: SDKConfig,
        hostOptions: LBUIOptions?,
        keyPath: KeyPath<SDKConfig.Visibility, Bool?>,
        hostKeyPath: KeyPath<SDKConfig.Visibility, Bool?>,
        templateDefault: Bool
    ) -> Bool {
        let sdkValue  = sdkConfig.visibility?[keyPath: keyPath]
        let hostValue = hostOptions?.visibility?[keyPath: hostKeyPath]
        return effectiveVisibility(sdkValue: sdkValue, hostValue: hostValue, templateDefault: templateDefault)
    }

    // MARK: - Layout map

    /// Merges a layout key from the three layers.
    /// - Parameters:
    ///   - sdkMap:          `sdkConfig.layout.player` or `.widget` (Layer 3).
    ///   - hostMap:         `hostOptions.layoutPlayer` or `.layoutWidget` (Layer 2).
    ///   - templateDefaults: Template's well-known key defaults (Layer 1).
    /// - Returns: Effective value for `key`, or nil if no layer has it.
    public static func effectiveLayoutValue(
        key: String,
        sdkMap: [String: Any]?,
        hostMap: [String: Any]?,
        templateDefaults: [String: Any]
    ) -> Any? {
        if let v = sdkMap?[key]          { return v }
        if let v = hostMap?[key]         { return v }
        return templateDefaults[key]
    }

    // MARK: - Theme

    public static func effectivePrimaryColor(
        sdkConfig: SDKConfig,
        hostOptions: LBUIOptions?,
        templateDefault: String?
    ) -> String? {
        if let v = sdkConfig.theme?.primaryColor { return v }
        if let v = hostOptions?.theme?.primaryColor { return v }
        return templateDefault
    }

    public static func effectiveFontScale(
        sdkConfig: SDKConfig,
        hostOptions: LBUIOptions?,
        templateDefault: Float?
    ) -> Float? {
        if let v = sdkConfig.theme?.fontScale { return v }
        if let v = hostOptions?.theme?.fontScale { return v }
        return templateDefault
    }
}
