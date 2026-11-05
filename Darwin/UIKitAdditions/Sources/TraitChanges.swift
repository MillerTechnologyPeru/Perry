// Registering for trait changes, iOS 17's replacement for
// traitCollectionDidChange(_:). Declarations are the SDK interface's.
// Perry's traits change only when a resizable window's size class does;
// the registrations are kept for the handlers' owners.

public import Foundation
import ObjectiveC

/// A registration: the traits, and the handler or target and action.
@available(iOS 17.0, tvOS 17.0, *)
final class _PerryTraitChangeRegistration: NSObject, UITraitChangeRegistration {
    let traits: [UIKit.UITrait]
    let handler: Any?
    weak var target: AnyObject?
    let action: Selector?

    init(traits: [UIKit.UITrait], handler: Any?, target: AnyObject?, action: Selector?) {
        (self.traits, self.handler, self.target, self.action) = (traits, handler, target, action)
    }

    func copy(with zone: NSZone? = nil) -> Any { self }
}

/// The registrations of an object, kept with it.
@available(iOS 17.0, tvOS 17.0, *)
enum _TraitChangeRegistrations {
    nonisolated(unsafe) private static var key: UInt8 = 0

    static func add(_ registration: _PerryTraitChangeRegistration, to owner: AnyObject) -> any UITraitChangeRegistration {
        var registrations = objc_getAssociatedObject(owner, &key) as? [_PerryTraitChangeRegistration] ?? []
        registrations.append(registration)
        objc_setAssociatedObject(owner, &key, registrations, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return registration
    }

    static func remove(_ registration: any UITraitChangeRegistration, from owner: AnyObject) {
        guard var registrations = objc_getAssociatedObject(owner, &key) as? [_PerryTraitChangeRegistration] else { return }
        registrations.removeAll { $0 === (registration as AnyObject) }
        objc_setAssociatedObject(owner, &key, registrations, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
@_Concurrency.MainActor public protocol UITraitChangeObservable {
  typealias TraitChangeHandler<TraitEnvironment> = (_ traitEnvironment: TraitEnvironment, _ previousTraitCollection: UITraitCollection) -> Swift.Void where TraitEnvironment : UITraitEnvironment
  @discardableResult
  @_Concurrency.MainActor func registerForTraitChanges<TraitEnvironment>(_ traits: [UIKit.UITrait], handler: @escaping Self.TraitChangeHandler<TraitEnvironment>) -> any UITraitChangeRegistration where TraitEnvironment : UITraitEnvironment
  @discardableResult
  @_Concurrency.MainActor func registerForTraitChanges(_ traits: [UIKit.UITrait], target: Any, action: ObjectiveC.Selector) -> any UITraitChangeRegistration
  @discardableResult
  @_Concurrency.MainActor func registerForTraitChanges(_ traits: [UIKit.UITrait], action: ObjectiveC.Selector) -> any UITraitChangeRegistration
  @_Concurrency.MainActor func unregisterForTraitChanges(_ registration: any UITraitChangeRegistration)
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIView : UIKit.UITraitChangeObservable {
  @discardableResult
  @_Concurrency.MainActor public func registerForTraitChanges<Self>(_ traits: [UIKit.UITrait], handler: @escaping UIView.TraitChangeHandler<Self>) -> any UITraitChangeRegistration where Self : UITraitEnvironment {
    _TraitChangeRegistrations.add(_PerryTraitChangeRegistration(traits: traits, handler: handler, target: nil, action: nil), to: self)
  }
  @discardableResult
  @_Concurrency.MainActor public func registerForTraitChanges(_ traits: [UIKit.UITrait], target: Any, action: ObjectiveC.Selector) -> any UITraitChangeRegistration {
    _TraitChangeRegistrations.add(_PerryTraitChangeRegistration(traits: traits, handler: nil, target: target as AnyObject, action: action), to: self)
  }
  @discardableResult
  @_Concurrency.MainActor public func registerForTraitChanges(_ traits: [UIKit.UITrait], action: ObjectiveC.Selector) -> any UITraitChangeRegistration {
    _TraitChangeRegistrations.add(_PerryTraitChangeRegistration(traits: traits, handler: nil, target: self, action: action), to: self)
  }
  @_Concurrency.MainActor public func unregisterForTraitChanges(_ registration: any UITraitChangeRegistration) {
    _TraitChangeRegistrations.remove(registration, from: self)
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIViewController : UIKit.UITraitChangeObservable {
  @discardableResult
  @_Concurrency.MainActor public func registerForTraitChanges<Self>(_ traits: [UIKit.UITrait], handler: @escaping UIViewController.TraitChangeHandler<Self>) -> any UITraitChangeRegistration where Self : UITraitEnvironment {
    _TraitChangeRegistrations.add(_PerryTraitChangeRegistration(traits: traits, handler: handler, target: nil, action: nil), to: self)
  }
  @discardableResult
  @_Concurrency.MainActor public func registerForTraitChanges(_ traits: [UIKit.UITrait], target: Any, action: ObjectiveC.Selector) -> any UITraitChangeRegistration {
    _TraitChangeRegistrations.add(_PerryTraitChangeRegistration(traits: traits, handler: nil, target: target as AnyObject, action: action), to: self)
  }
  @discardableResult
  @_Concurrency.MainActor public func registerForTraitChanges(_ traits: [UIKit.UITrait], action: ObjectiveC.Selector) -> any UITraitChangeRegistration {
    _TraitChangeRegistrations.add(_PerryTraitChangeRegistration(traits: traits, handler: nil, target: self, action: action), to: self)
  }
  @_Concurrency.MainActor public func unregisterForTraitChanges(_ registration: any UITraitChangeRegistration) {
    _TraitChangeRegistrations.remove(registration, from: self)
  }
}
