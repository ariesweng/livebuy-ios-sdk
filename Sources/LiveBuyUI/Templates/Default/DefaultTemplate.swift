import LiveBuySDK

/// Default built-in template.  Handles all SDK events with a standard live-shopping UI.
/// Install via `LiveBuyUI.install(template: DefaultTemplate())`.
///
/// Spec: `ui-template-foundation/spec.md` § "Default Template 事件覆蓋範圍"
public final class DefaultTemplate: AnyLBTemplate {

    public init() {}
}
