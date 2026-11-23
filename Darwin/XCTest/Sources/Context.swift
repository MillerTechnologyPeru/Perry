import Foundation
import XCUIAutomation

// XCTContext's activities as Swift, and typing a key with modifiers into a
// UI element (XCUIElement was part of XCTest when its Swift 5.0 overlay
// was built, so the overlay keeps the method).

extension XCTContext {
    @preconcurrency @MainActor
    public class func runActivity<Result>(named name: String, block: @MainActor (any XCTActivity) throws -> Result) rethrows -> Result {
        var result: Swift.Result<Result, any Error>?
        return try withoutActuallyEscaping(block) { block in
            __runActivityNamed(name) { activity in
                result = MainActor.assumeIsolated { Swift.Result { try block(activity) } }
            }
            return try result!.get()
        }
    }
}

/// -[XCUIElement typeKey:modifierFlags:].
private typealias TypeKey = @convention(c) (XCUIElement, Selector, NSString, XCUIElement.KeyModifierFlags) -> Void

extension XCUIElement {
    @nonobjc
    public func typeKey(_ key: XCUIKeyboardKey, modifierFlags: XCUIElement.KeyModifierFlags) {
        let selector = NSSelectorFromString("typeKey:modifierFlags:")
        let typeKey = unsafeBitCast(method(for: selector), to: TypeKey.self)
        typeKey(self, selector, key.rawValue as NSString, modifierFlags)
    }
}
