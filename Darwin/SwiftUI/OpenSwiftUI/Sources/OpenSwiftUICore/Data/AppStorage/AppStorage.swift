//
//  AppStorage.swift
//  OpenSwiftUICore
//
//  Status: Complete for Perry

public import Foundation
import OpenAttributeGraphShims
#if OPENSWIFTUI_OPENCOMBINE
import OpenCombine
#else
import Combine
#endif

// MARK: - AppStorage

/// A property wrapper type that reflects a value from `UserDefaults` and
/// invalidates a view on a change in value in that user default.
///
/// The value is read from the store each time, so a change made elsewhere
/// (another view, or `UserDefaults` directly) shows on the next update; a
/// change through the property also redraws the views that read it.
@available(OpenSwiftUI_v2_0, *)
@frozen
@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    @usableFromInline
    internal var location: UserDefaultLocation<Value>

    init(location: UserDefaultLocation<Value>) {
        self.location = location
    }

    public var wrappedValue: Value {
        get { location.get() }
        nonmutating set { location.set(newValue, transaction: Transaction()) }
    }

    public var projectedValue: Binding<Value> {
        Binding(value: location.get(), location: location)
    }

    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        let attribute = Attribute(value: ())
        let box = AppStoragePropertyBox<Value>(host: .currentHost, invalidation: WeakAttribute(attribute))
        buffer.append(box, fieldOffset: fieldOffset)
    }
}

@available(OpenSwiftUI_v2_0, *)
extension AppStorage: Sendable where Value: Sendable {}

/// Subscribes the view to its user default's changes.
private struct AppStoragePropertyBox<Value>: DynamicPropertyBox {
    typealias Upstream = PassthroughSubject<Void, Never>
    typealias Property = AppStorage<Value>

    let subscriber: AttributeInvalidatingSubscriber<Upstream>
    let lifetime: SubscriptionLifetime<Upstream> = .init()
    var lastLocation: UserDefaultLocation<Value>?

    init(host: GraphHost, invalidation: WeakAttribute<()>) {
        subscriber = .init(host: host, attribute: invalidation)
    }

    mutating func update(property: inout Property, phase: ViewPhase) -> Bool {
        let location = property.location
        if lastLocation !== location || lifetime.isUninitialized {
            lifetime.subscribe(subscriber: subscriber, to: location.changes)
        }
        lastLocation = location
        return subscriber.attribute.changedValue()?.changed ?? false
    }
}

// MARK: - UserDefaultLocation

/// Where an `AppStorage` value lives: a key in a store, with how the value
/// is read and written there, and the value used while the key is unset.
@usableFromInline
internal class UserDefaultLocation<Value>: AnyLocation<Value>, @unchecked Sendable {
    let key: String
    let store: UserDefaults
    let defaultValue: Value
    let read: (UserDefaults, String) -> Value?
    let write: (UserDefaults, String, Value) -> Void
    /// Sends when the value may have changed.
    let changes = PassthroughSubject<Void, Never>()
    private var observer: NSObjectProtocol?
    private var _wasRead = false

    init(
        key: String,
        store: UserDefaults?,
        defaultValue: Value,
        read: @escaping (UserDefaults, String) -> Value?,
        write: @escaping (UserDefaults, String, Value) -> Void
    ) {
        self.key = key
        self.store = store ?? .standard
        self.defaultValue = defaultValue
        self.read = read
        self.write = write
        super.init()
        let changes = changes
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: self.store,
            queue: nil
        ) { _ in changes.send() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    @usableFromInline
    override var wasRead: Bool {
        get { _wasRead }
        set { _wasRead = newValue }
    }

    @usableFromInline
    override func get() -> Value {
        _wasRead = true
        guard store.object(forKey: key) != nil, let value = read(store, key) else { return defaultValue }
        return value
    }

    @usableFromInline
    override func set(_ value: Value, transaction: Transaction) {
        write(store, key, value)
        changes.send()
    }

    @usableFromInline
    override func update() -> (Value, Bool) {
        (get(), true)
    }

    @usableFromInline
    static func == (lhs: UserDefaultLocation<Value>, rhs: UserDefaultLocation<Value>) -> Bool {
        lhs.key == rhs.key && lhs.store === rhs.store
    }
}

// MARK: - Initializers

@available(OpenSwiftUI_v2_0, *)
extension AppStorage {
    private init(
        _ key: String, store: UserDefaults?, defaultValue: Value,
        read: @escaping (UserDefaults, String) -> Value?,
        write: @escaping (UserDefaults, String, Value) -> Void
    ) {
        self.init(location: UserDefaultLocation(key: key, store: store, defaultValue: defaultValue, read: read, write: write))
    }

    /// A value the store keeps as itself (a property list value).
    private init(direct key: String, store: UserDefaults?, defaultValue: Value) {
        self.init(key, store: store, defaultValue: defaultValue,
                  read: { $0.object(forKey: $1) as? Value },
                  write: { $0.set($2, forKey: $1) })
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {
        self.init(direct: key, store: store, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {
        self.init(direct: key, store: store, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {
        self.init(direct: key, store: store, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {
        self.init(direct: key, store: store, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == URL {
        self.init(key, store: store, defaultValue: wrappedValue,
                  read: { $0.url(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }

    @available(OpenSwiftUI_v6_0, *)
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Date {
        self.init(direct: key, store: store, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {
        self.init(direct: key, store: store, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
        where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key, store: store, defaultValue: wrappedValue,
                  read: { ($0.object(forKey: $1) as? Int).flatMap(Value.init(rawValue:)) },
                  write: { $0.set($2.rawValue, forKey: $1) })
    }

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
        where Value: RawRepresentable, Value.RawValue == String {
        self.init(key, store: store, defaultValue: wrappedValue,
                  read: { $0.string(forKey: $1).flatMap(Value.init(rawValue:)) },
                  write: { $0.set($2.rawValue, forKey: $1) })
    }
}

@available(OpenSwiftUI_v2_0, *)
extension AppStorage where Value: ExpressibleByNilLiteral {
    /// An optional value: setting nil removes the key.
    private init<Wrapped>(optional key: String, store: UserDefaults?, as type: Wrapped.Type) where Value == Wrapped? {
        self.init(key, store: store, defaultValue: nil,
                  read: { $0.object(forKey: $1) as? Wrapped },
                  write: { store, key, value in
                      if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
                  })
    }

    public init(_ key: String, store: UserDefaults? = nil) where Value == Bool? { self.init(optional: key, store: store, as: Bool.self) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Int? { self.init(optional: key, store: store, as: Int.self) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Double? { self.init(optional: key, store: store, as: Double.self) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == String? { self.init(optional: key, store: store, as: String.self) }

    public init(_ key: String, store: UserDefaults? = nil) where Value == URL? {
        self.init(key, store: store, defaultValue: nil,
                  read: { $0.url(forKey: $1) },
                  write: { store, key, value in
                      if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
                  })
    }

    @available(OpenSwiftUI_v6_0, *)
    public init(_ key: String, store: UserDefaults? = nil) where Value == Date? { self.init(optional: key, store: store, as: Date.self) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Data? { self.init(optional: key, store: store, as: Data.self) }
}

@available(OpenSwiftUI_v3_0, *)
extension AppStorage {
    public init<R>(_ key: String, store: UserDefaults? = nil) where Value == R?, R: RawRepresentable, R.RawValue == String {
        self.init(key, store: store, defaultValue: nil,
                  read: { $0.string(forKey: $1).flatMap(R.init(rawValue:)) },
                  write: { store, key, value in
                      if let value { store.set(value.rawValue, forKey: key) } else { store.removeObject(forKey: key) }
                  })
    }

    public init<R>(_ key: String, store: UserDefaults? = nil) where Value == R?, R: RawRepresentable, R.RawValue == Int {
        self.init(key, store: store, defaultValue: nil,
                  read: { ($0.object(forKey: $1) as? Int).flatMap(R.init(rawValue:)) },
                  write: { store, key, value in
                      if let value { store.set(value.rawValue, forKey: key) } else { store.removeObject(forKey: key) }
                  })
    }
}
