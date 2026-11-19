// AppIntents: the actions an app offers Siri, Shortcuts and Spotlight.
// None of those run here, so no intent is ever performed; what is here
// is what an app does with the framework on its own as it starts: it
// registers the dependencies its intents would use, and tells the
// system its shortcuts' parameters changed. The declarations are the
// framework's own (what apps bind to by Swift symbol), so library
// evolution is on and the types are resilient.
import Foundation

// MARK: - Dependencies

/// The dependencies an app registers for its intents, by key or, without
/// one, by type.
@available(iOS 16.0, *)
final public class AppDependencyManager {
    nonisolated(unsafe) public static let shared = AppDependencyManager()

    private let lock = NSLock()
    private var providers: [AnyHashable: Provider] = [:]

    enum Provider {
        case value(() throws -> Any)
        case asynchronous(() async throws -> Any)
    }

    public init() {}

    @_silgen_name("$s10AppIntents0A17DependencyManagerC3add3key10dependencyys11AnyHashableVSg_xyXAts8SendableRzlF")
    @_disfavoredOverload final public func add<Dependency>(key: AnyHashable? = nil, dependency dependencyProvider: @autoclosure @escaping @Sendable () -> Dependency) where Dependency: Sendable {
        store(.value { dependencyProvider() }, key: key, type: Dependency.self)
    }

    @_silgen_name("$s10AppIntents0A17DependencyManagerC3add3key10dependencyys11AnyHashableVSg_xyKcyXAts8SendableRzlF")
    final public func add<Dependency>(key: AnyHashable? = nil, dependency dependencyProvider: @autoclosure @escaping () -> @Sendable () throws -> Dependency) where Dependency: Sendable {
        store(.value { try dependencyProvider()() }, key: key, type: Dependency.self)
    }

    @_silgen_name("$s10AppIntents0A17DependencyManagerC3add3key10dependencyys11AnyHashableVSg_xyYaKcts8SendableRzlF")
    final public func add<Dependency>(key: AnyHashable? = nil, dependency dependencyProvider: @escaping @Sendable () async throws -> Dependency) where Dependency: Sendable {
        store(.asynchronous { try await dependencyProvider() }, key: key, type: Dependency.self)
    }

    private func store(_ provider: Provider, key: AnyHashable?, type: Any.Type) {
        lock.lock()
        providers[key ?? AnyHashable(ObjectIdentifier(type))] = provider
        lock.unlock()
    }

    func provider(key: AnyHashable?, type: Any.Type) -> (AnyHashable, Provider?) {
        let key = key ?? AnyHashable(ObjectIdentifier(type))
        lock.lock()
        defer { lock.unlock() }
        return (key, providers[key])
    }
}

@available(iOS 16.0, *)
extension AppDependencyManager {
    public enum Error<Value>: LocalizedError, @unchecked Sendable {
        case failedToRetrieveDependency(AnyHashable, Value.Type)
        case failedToLoadDependency(AnyHashable, Value.Type)
        case incorrectDependencyType(AnyHashable, Value.Type, any Any.Type)

        public var errorDescription: String? {
            switch self {
            case .failedToRetrieveDependency(let key, let type):
                return "No dependency of type \(type) was registered for \(key)."
            case .failedToLoadDependency(let key, let type):
                return "The dependency of type \(type) for \(key) failed to load."
            case .incorrectDependencyType(let key, let type, let actual):
                return "The dependency for \(key) is a \(actual), not a \(type)."
            }
        }
    }
}

/// An intent's dependency, found in the manager when it is first read.
@available(iOS 16.0, *)
@propertyWrapper final public class AppDependency<Value>: @unchecked Sendable where Value: Sendable {
    private let key: AnyHashable?
    private let manager: AppDependencyManager
    private let defaultValue: (() -> Value)?
    private let lock = NSLock()
    private var value: Value?

    init(key: AnyHashable?, manager: AppDependencyManager, defaultValue: (() -> Value)?) {
        self.key = key
        self.manager = manager
        self.defaultValue = defaultValue
    }

    final public var projectedValue: AppDependency<Value> { self }

    final public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            let resolved = resolve()
            value = resolved
            return resolved
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private func resolve() -> Value {
        let (key, provider) = manager.provider(key: self.key, type: Value.self)
        switch provider {
        case .value(let make)?:
            do {
                let made = try make()
                guard let value = made as? Value else {
                    fatalError(AppDependencyManager.Error<Value>.incorrectDependencyType(key, Value.self, type(of: made)).errorDescription!)
                }
                return value
            } catch {
                fatalError(AppDependencyManager.Error<Value>.failedToLoadDependency(key, Value.self).errorDescription!)
            }
        case .asynchronous?:
            // Intents are never performed here, so nothing waits for one.
            fatalError("perry: AppIntents: the dependency of type \(Value.self) for \(key) loads asynchronously, which is not supported")
        case nil:
            if let defaultValue { return defaultValue() }
            fatalError(AppDependencyManager.Error<Value>.failedToRetrieveDependency(key, Value.self).errorDescription!)
        }
    }

    convenience public init(key: AnyHashable? = nil, manager: AppDependencyManager = .shared) {
        self.init(key: key, manager: manager, defaultValue: nil)
    }

    convenience public init(key: AnyHashable? = nil, manager: AppDependencyManager = .shared, default defaultValueProvider: @autoclosure @escaping () -> Value) {
        self.init(key: key, manager: manager, defaultValue: defaultValueProvider)
    }

    convenience public init(key: AnyHashable? = nil, manager: AppDependencyManager = .shared, default defaultValueProvider: @escaping () async throws -> Value) {
        self.init(key: key, manager: manager, defaultValue: nil)
    }
}

// MARK: - Shortcuts

/// `AppShortcutsProvider.updateAppShortcutParameters()`: tells the system
/// the app's shortcuts' parameters changed. There is no Shortcuts app to
/// tell. The protocol is not declared here, so the extension member is
/// defined by its symbol; it takes no arguments of its own.
@_silgen_name("$s10AppIntents0A17ShortcutsProviderPAAE06updateA18ShortcutParametersyyFZ")
public func _appShortcutsProviderUpdateAppShortcutParameters() {}
