// MusicKit: Apple Music's catalog and the user's library. There is no Apple
// Music here: the app's access to it is denied and stays so, and asking for
// it answers the same. The declarations are the framework's own (what apps
// bind to by Swift symbol), so library evolution is on and the types are
// resilient.
import Foundation

/// The app's access to Apple Music.
@available(iOS 15.0, *)
public struct MusicAuthorization {
    /// Denied: there is no Apple Music to use.
    public static var currentStatus: MusicAuthorization.Status { .denied }

    /// Asks for access, which is not given.
    public static func request() async -> MusicAuthorization.Status { .denied }
}

@available(iOS 15.0, *)
extension MusicAuthorization {
    public enum Status: String, Sendable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }
}

@available(iOS 15.0, *)
extension MusicAuthorization.Status: CustomStringConvertible {
    public var description: String { rawValue }
}
