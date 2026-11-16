//
//  SceneStorage.swift
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

// MARK: - SceneStorage

/// A property wrapper type that reads and writes to persisted, per-scene
/// storage.
///
/// Perry runs one scene and restores none: the values are kept by key for
/// the life of the process, shared by the views that name the key, and a
/// change redraws the views that read it.
@available(OpenSwiftUI_v2_0, *)
@frozen
@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    @usableFromInline
    internal var _key: String
    @usableFromInline
    internal var _domain: String?
    @usableFromInline
    internal var _value: Value
    @usableFromInline
    internal var _location: AnyLocation<Value>?
    @usableFromInline
    internal var _transformBox: SceneStorageTransformBox

    init(key: String, defaultValue: Value) {
        _key = key
        _domain = nil
        _value = defaultValue
        _location = SceneStorageLocation(key: key, defaultValue: defaultValue)
        _transformBox = SceneStorageTransformBox()
    }

    public var wrappedValue: Value {
        get { _location?.get() ?? _value }
        nonmutating set { _location?.set(newValue, transaction: Transaction()) }
    }

    public var projectedValue: Binding<Value> {
        guard let _location else { return .constant(_value) }
        return Binding(value: _location.get(), location: _location)
    }

    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        let attribute = Attribute(value: ())
        let box = SceneStoragePropertyBox<Value>(host: .currentHost, invalidation: WeakAttribute(attribute))
        buffer.append(box, fieldOffset: fieldOffset)
    }
}

@available(OpenSwiftUI_v2_0, *)
extension SceneStorage: @unchecked Sendable where Value: Sendable {}

/// How a value is kept: nothing here, as the values are held as they are.
@available(OpenSwiftUI_v2_0, *)
@usableFromInline
internal class SceneStorageTransformBox {
    init() {}

    @usableFromInline
    deinit {}
}

/// Subscribes the view to its key's changes.
private struct SceneStoragePropertyBox<Value>: DynamicPropertyBox {
    typealias Upstream = PassthroughSubject<Void, Never>
    typealias Property = SceneStorage<Value>

    let subscriber: AttributeInvalidatingSubscriber<Upstream>
    let lifetime: SubscriptionLifetime<Upstream> = .init()
    var lastKey: String?

    init(host: GraphHost, invalidation: WeakAttribute<()>) {
        subscriber = .init(host: host, attribute: invalidation)
    }

    mutating func update(property: inout Property, phase: ViewPhase) -> Bool {
        if lastKey != property._key || lifetime.isUninitialized {
            lifetime.subscribe(subscriber: subscriber, to: SceneStorageStore.changes(for: property._key))
        }
        lastKey = property._key
        return subscriber.attribute.changedValue()?.changed ?? false
    }
}

// MARK: - The store

/// The scene's values by key, and who hears of each key's changes. Views
/// read and write them on the main thread.
private enum SceneStorageStore {
    nonisolated(unsafe) static var values: [String: Any] = [:]
    nonisolated(unsafe) static var subjects: [String: PassthroughSubject<Void, Never>] = [:]

    static func changes(for key: String) -> PassthroughSubject<Void, Never> {
        if let subject = subjects[key] { return subject }
        let subject = PassthroughSubject<Void, Never>()
        subjects[key] = subject
        return subject
    }
}

/// Where a `SceneStorage` value lives: a key of the scene's store, with
/// the value used while the key is unset.
private final class SceneStorageLocation<Value>: AnyLocation<Value>, @unchecked Sendable {
    let key: String
    let defaultValue: Value
    private var _wasRead = false

    init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
        super.init()
    }

    override var wasRead: Bool {
        get { _wasRead }
        set { _wasRead = newValue }
    }

    override func get() -> Value {
        _wasRead = true
        return SceneStorageStore.values[key] as? Value ?? defaultValue
    }

    override func set(_ value: Value, transaction: Transaction) {
        SceneStorageStore.values[key] = value
        SceneStorageStore.changes(for: key).send()
    }

    override func update() -> (Value, Bool) {
        (get(), true)
    }

    static func == (lhs: SceneStorageLocation<Value>, rhs: SceneStorageLocation<Value>) -> Bool {
        lhs.key == rhs.key
    }
}

// MARK: - Initializers

@available(OpenSwiftUI_v2_0, *)
extension SceneStorage {
    public init(wrappedValue: Value, _ key: String) where Value == Bool { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == Int { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == Double { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == String { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == URL { self.init(key: key, defaultValue: wrappedValue) }

    @available(OpenSwiftUI_v6_0, *)
    public init(wrappedValue: Value, _ key: String) where Value == Date { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == Data { self.init(key: key, defaultValue: wrappedValue) }

    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key: key, defaultValue: wrappedValue)
    }

    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == String {
        self.init(key: key, defaultValue: wrappedValue)
    }
}

@available(OpenSwiftUI_v2_0, *)
extension SceneStorage where Value: ExpressibleByNilLiteral {
    public init(_ key: String) where Value == Bool? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == Int? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == Double? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == String? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == URL? { self.init(key: key, defaultValue: nil) }

    @available(OpenSwiftUI_v6_0, *)
    public init(_ key: String) where Value == Date? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == Data? { self.init(key: key, defaultValue: nil) }
}

@available(OpenSwiftUI_v3_0, *)
extension SceneStorage {
    public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue == String {
        self.init(key: key, defaultValue: nil)
    }

    public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue == Int {
        self.init(key: key, defaultValue: nil)
    }
}
