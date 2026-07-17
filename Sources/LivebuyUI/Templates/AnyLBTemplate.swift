import LivebuySDK

/// Base protocol for all LivebuyUI templates.
/// Templates receive the effective merged config at Widget / Player instantiate time
/// and are responsible for handling SDK events through the event listener.
public protocol AnyLBTemplate: AnyObject {}
