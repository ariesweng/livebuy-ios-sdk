import LiveBuySDK

/// Base protocol for all LiveBuyUI templates.
/// Templates receive the effective merged config at Widget / Player instantiate time
/// and are responsible for handling SDK events through the event listener.
public protocol AnyLBTemplate: AnyObject {}
