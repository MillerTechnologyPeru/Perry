import Foundation

// AVAsyncProperty and loading it: AVAsynchronousKeyValueLoading's
// loadValuesAsynchronously(forKeys:) for the property's key, then its
// status and, once loaded, the value its getter reads from the object.

@_hasMissingDesignatedInitializers
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
public class AVAnyAsyncProperty: CustomStringConvertible, @unchecked Sendable {
    init() {}

    public var description: String { "AVAnyAsyncProperty" }
}

@_hasMissingDesignatedInitializers
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
public class AVPartialAsyncProperty<Root>: AVAnyAsyncProperty, @unchecked Sendable {
    /// The key loadValuesAsynchronously(forKeys:) and
    /// statusOfValue(forKey:error:) take.
    @usableFromInline
    final let key: String

    init(key: String) {
        self.key = key
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    @usableFromInline
    var usableFromInlineKey: String { key }

    /// The key as the last component of the description, which ends with
    /// it, as code built for systems before the key was public reads it.
    @usableFromInline
    final var keyFromDescription: String {
        guard let key = description.split(separator: ".").last else { return self.key }
        return String(key)
    }

    @usableFromInline
    final var backDeployedKey: String { key }

    /// The root type and the key: "AVAsset.duration".
    public override var description: String { "\(Root.self).\(key)" }
}

@_hasMissingDesignatedInitializers
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
public class AVAsyncProperty<Root, Value>: AVPartialAsyncProperty<Root>, @unchecked Sendable {
    /// Reads the loaded value from an object of the root type.
    let getter: (Root) -> Value

    init(key: String, getter: @escaping (Root) -> Value) {
        self.getter = getter
        super.init(key: key)
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAsyncProperty {
    @frozen public enum Status {
        case notYetLoaded
        case loading
        case loaded(Value)
        case failed(NSError)
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAsyncProperty.Status: Equatable where Value: Equatable {
    public static func == (lhs: AVAsyncProperty<Root, Value>.Status, rhs: AVAsyncProperty<Root, Value>.Status) -> Bool {
        switch (lhs, rhs) {
        case (.notYetLoaded, .notYetLoaded), (.loading, .loading): return true
        case let (.loaded(a), .loaded(b)): return a == b
        case let (.failed(a), .failed(b)): return a == b
        default: return false
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAsyncProperty.Status: Sendable where Value: Sendable {}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAsyncProperty.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notYetLoaded: return "notYetLoaded"
        case .loading: return "loading"
        case let .loaded(value): return "loaded(\(value))"
        case let .failed(error): return "failed(\(error))"
        }
    }
}

/// The error of a property that failed to load without one of its own.
private func loadingError(_ key: String) -> NSError {
    NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Loading \(key) failed"])
}

extension AVAsynchronousKeyValueLoading {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    public func status<T>(of property: AVAsyncProperty<Self, T>) -> AVAsyncProperty<Self, T>.Status {
        var error: NSError?
        switch statusOfValue(forKey: property.key, error: &error) {
        case .loaded:
            return .loaded(property.getter(self))
        case .loading:
            return .loading
        case .failed:
            return .failed(error ?? loadingError(property.key))
        case .cancelled:
            return .failed(error ?? NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        default:
            return .notYetLoaded
        }
    }

    /// The value of a loaded property, or its error.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    func value<T>(of loadedProperty: AVAsyncProperty<Self, T>) throws -> T {
        switch status(of: loadedProperty) {
        case let .loaded(value):
            return value
        case let .failed(error):
            throw error
        default:
            // Loading finished without a status of either: read it anyway.
            return loadedProperty.getter(self)
        }
    }

    /// Loads the keys, returning when they're loaded or failed.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    private func loadKeys(_ keys: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadValuesAsynchronously(forKeys: keys) { continuation.resume() }
        }
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd__AC15AVAsyncPropertyCyxqd__GYaKlF")
    func __loadForABI<T>(_ property: AVAsyncProperty<Self, T>) async throws -> T {
        await loadKeys([property.key])
        return try value(of: property)
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    public func load<T>(_ property: AVAsyncProperty<Self, T>, isolation: isolated (any Actor)? = #isolation) async throws -> T {
        await loadKeys([property.key])
        return try value(of: property)
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    public func load<A, B, each C>(_ firstProperty: AVAsyncProperty<Self, A>, _ secondProperty: AVAsyncProperty<Self, B>, _ properties: repeat AVAsyncProperty<Self, each C>, isolation: isolated (any Actor)? = #isolation) async throws -> (A, B, repeat each C) {
        var keys = [firstProperty.key, secondProperty.key]
        for property in repeat each properties {
            keys.append(property.key)
        }
        await loadKeys(keys)
        return (try value(of: firstProperty), try value(of: secondProperty), repeat try value(of: each properties))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GtYaKr0_lF")
    func __loadForABI<A, B>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>) async throws -> (A, B) {
        await loadKeys([propertyA.key, propertyB.key])
        return (try value(of: propertyA), try value(of: propertyB))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_qd_1_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GAFyxqd_1_GtYaKr1_lF")
    func __loadForABI<A, B, C>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>, _ propertyC: AVAsyncProperty<Self, C>) async throws -> (A, B, C) {
        await loadKeys([propertyA.key, propertyB.key, propertyC.key])
        return (try value(of: propertyA), try value(of: propertyB), try value(of: propertyC))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_qd_1_qd_2_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GAFyxqd_1_GAFyxqd_2_GtYaKr2_lF")
    func __loadForABI<A, B, C, D>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>, _ propertyC: AVAsyncProperty<Self, C>, _ propertyD: AVAsyncProperty<Self, D>) async throws -> (A, B, C, D) {
        await loadKeys([propertyA.key, propertyB.key, propertyC.key, propertyD.key])
        return (try value(of: propertyA), try value(of: propertyB), try value(of: propertyC), try value(of: propertyD))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_qd_1_qd_2_qd_3_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GAFyxqd_1_GAFyxqd_2_GAFyxqd_3_GtYaKr3_lF")
    func __loadForABI<A, B, C, D, E>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>, _ propertyC: AVAsyncProperty<Self, C>, _ propertyD: AVAsyncProperty<Self, D>, _ propertyE: AVAsyncProperty<Self, E>) async throws -> (A, B, C, D, E) {
        await loadKeys([propertyA.key, propertyB.key, propertyC.key, propertyD.key, propertyE.key])
        return (try value(of: propertyA), try value(of: propertyB), try value(of: propertyC), try value(of: propertyD), try value(of: propertyE))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_qd_1_qd_2_qd_3_qd_4_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GAFyxqd_1_GAFyxqd_2_GAFyxqd_3_GAFyxqd_4_GtYaKr4_lF")
    func __loadForABI<A, B, C, D, E, F>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>, _ propertyC: AVAsyncProperty<Self, C>, _ propertyD: AVAsyncProperty<Self, D>, _ propertyE: AVAsyncProperty<Self, E>, _ propertyF: AVAsyncProperty<Self, F>) async throws -> (A, B, C, D, E, F) {
        await loadKeys([propertyA.key, propertyB.key, propertyC.key, propertyD.key, propertyE.key, propertyF.key])
        return (try value(of: propertyA), try value(of: propertyB), try value(of: propertyC), try value(of: propertyD), try value(of: propertyE), try value(of: propertyF))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_qd_1_qd_2_qd_3_qd_4_qd_5_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GAFyxqd_1_GAFyxqd_2_GAFyxqd_3_GAFyxqd_4_GAFyxqd_5_GtYaKr5_lF")
    func __loadForABI<A, B, C, D, E, F, G>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>, _ propertyC: AVAsyncProperty<Self, C>, _ propertyD: AVAsyncProperty<Self, D>, _ propertyE: AVAsyncProperty<Self, E>, _ propertyF: AVAsyncProperty<Self, F>, _ propertyG: AVAsyncProperty<Self, G>) async throws -> (A, B, C, D, E, F, G) {
        await loadKeys([propertyA.key, propertyB.key, propertyC.key, propertyD.key, propertyE.key, propertyF.key, propertyG.key])
        return (try value(of: propertyA), try value(of: propertyB), try value(of: propertyC), try value(of: propertyD), try value(of: propertyE), try value(of: propertyF), try value(of: propertyG))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @usableFromInline
    @_silgen_name("$sSo29AVAsynchronousKeyValueLoadingP12AVFoundationE4loadyqd___qd_0_qd_1_qd_2_qd_3_qd_4_qd_5_qd_6_tAC15AVAsyncPropertyCyxqd__G_AFyxqd_0_GAFyxqd_1_GAFyxqd_2_GAFyxqd_3_GAFyxqd_4_GAFyxqd_5_GAFyxqd_6_GtYaKr6_lF")
    func __loadForABI<A, B, C, D, E, F, G, H>(_ propertyA: AVAsyncProperty<Self, A>, _ propertyB: AVAsyncProperty<Self, B>, _ propertyC: AVAsyncProperty<Self, C>, _ propertyD: AVAsyncProperty<Self, D>, _ propertyE: AVAsyncProperty<Self, E>, _ propertyF: AVAsyncProperty<Self, F>, _ propertyG: AVAsyncProperty<Self, G>, _ propertyH: AVAsyncProperty<Self, H>) async throws -> (A, B, C, D, E, F, G, H) {
        await loadKeys([propertyA.key, propertyB.key, propertyC.key, propertyD.key, propertyE.key, propertyF.key, propertyG.key, propertyH.key])
        return (try value(of: propertyA), try value(of: propertyB), try value(of: propertyC), try value(of: propertyD), try value(of: propertyE), try value(of: propertyF), try value(of: propertyG), try value(of: propertyH))
    }
}
