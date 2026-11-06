// Foundation's objects as AnyHashable take the value types they bridge to,
// as Darwin's Foundation has them: an NSString key is equal to a String
// key, so a Swift [AnyHashable: Any] bridged to NSDictionary finds the keys
// Objective-C code gives it back, and an NSURL in an AnyHashable is equal
// to the URL.
//
// NSNumber's representation (which keeps numbers of different types equal)
// and NSMeasurement's are not here yet.

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSString: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(String._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSDate: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Date._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSData: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Data._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSURL: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Foundation.URL._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSURLComponents: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(URLComponents._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSUUID: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Foundation.UUID._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSLocale: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Locale._unconditionallyBridgeFromObjectiveC(self))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSCalendar: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Calendar._unconditionallyBridgeFromObjectiveC(self))
    }
}

// Collections as Swift's, of AnyHashable elements: their elements must be
// hashable, as Darwin's Foundation requires too.

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSArray: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(self as! [AnyHashable])
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSDictionary: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(self as! [AnyHashable: AnyHashable])
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSSet: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(self as! Set<AnyHashable>)
    }
}
