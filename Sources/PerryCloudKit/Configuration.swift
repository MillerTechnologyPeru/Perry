import Glibc

// How CloudKit is backed. By default there is no iCloud account. With
// PERRY_CLOUDKIT_API_TOKEN set, and Perry built with PERRY_CLOUDKIT_MISTKIT=1
// (see Package.swift), requests go to CloudKit Web Services through MistKit.

struct CloudKitConfiguration {
    enum Environment: String { case development, production }

    /// The container's API token, from the CloudKit Console.
    let apiToken: String
    /// A signed-in user's web authentication token, for the private and shared databases.
    let webAuthToken: String?
    let environment: Environment
    /// Used instead of the container identifier the app asks for.
    let container: String?

    private static func variable(_ name: String) -> String? {
        guard let value = getenv(name).map({ String(cString: $0) }), !value.isEmpty else { return nil }
        return value
    }

    /// Nil unless PERRY_CLOUDKIT_API_TOKEN is set and the MistKit backend is built in.
    nonisolated(unsafe) static let current: CloudKitConfiguration? = {
        #if PERRY_MISTKIT
        guard let apiToken = variable("PERRY_CLOUDKIT_API_TOKEN") else { return nil }
        return CloudKitConfiguration(
            apiToken: apiToken,
            webAuthToken: variable("PERRY_CLOUDKIT_WEB_AUTH_TOKEN"),
            environment: variable("PERRY_CLOUDKIT_ENVIRONMENT").flatMap { Environment(rawValue: $0.lowercased()) } ?? .production,
            container: variable("PERRY_CLOUDKIT_CONTAINER"))
        #else
        if variable("PERRY_CLOUDKIT_API_TOKEN") != nil {
            CloudTrace.say("PERRY_CLOUDKIT_API_TOKEN is set, but this Perry was built without PERRY_CLOUDKIT_MISTKIT=1")
        }
        return nil
        #endif
    }()
}
