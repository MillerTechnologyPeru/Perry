import Foundation

// CallKit's Swift API: a provider configuration's handle types as a set of
// CXHandle.HandleType, which the header gives as a set of NSNumbers.

@available(iOS 10.0, macCatalyst 13.0, macOS 10.12, watchOS 9.0, *)
@available(macOS, unavailable)
extension CXProviderConfiguration {
    @nonobjc
    public final var supportedHandleTypes: Set<CXHandle.HandleType> {
        get {
            Set(__supportedHandleTypes.compactMap { CXHandle.HandleType(rawValue: $0.intValue) })
        }
        set {
            __supportedHandleTypes = Set(newValue.map { NSNumber(value: $0.rawValue) })
        }
    }
}
