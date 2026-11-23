import Foundation

// XCTSkip: the error a test throws to be skipped. XCTest recognizes it by
// its user info, which carries a skipped-test context (XCTest's own class,
// made through the runtime since no header declares it) and asks for the
// error not to be recorded as a failure.

/// XCTest's user info keys for a skip, which it exports but no header
/// declares.
@_silgen_name("XCTestErrorUserInfoKeyShouldIgnore") private func shouldIgnoreKeySymbol()
@_silgen_name("XCTestErrorUserInfoKeySkippedTestContext") private func skippedTestContextKeySymbol()

/// The NSString a constant's symbol holds.
private func string(at symbol: @convention(thin) () -> Void, fallback: String) -> String {
    let address = unsafeBitCast(symbol, to: UnsafeRawPointer.self)
    guard let object = address.load(as: UnsafeRawPointer?.self) else { return fallback }
    return Unmanaged<NSString>.fromOpaque(object).takeUnretainedValue() as String
}

private let shouldIgnoreKey = string(at: shouldIgnoreKeySymbol, fallback: "XCTestErrorUserInfoKeyShouldIgnore")
private let skippedTestContextKey = string(at: skippedTestContextKeySymbol,
                                           fallback: "XCTestErrorUserInfoKeySkippedTestContext")

/// XCTSkippedTestContext's -initWithExplanation:evaluatedExpression:message:sourceCodeContext:.
private typealias MakeContext = @convention(c) (AnyObject, Selector, NSString?, NSString?, NSString?, XCTSourceCodeContext) -> Unmanaged<AnyObject>?

/// A skipped-test context for a message at a place in the source.
private func skippedTestContext(message: String?, file: StaticString, line: UInt) -> AnyObject? {
    guard let contextClass = NSClassFromString("XCTSkippedTestContext") as? NSObject.Type else { return nil }
    let selector = NSSelectorFromString("initWithExplanation:evaluatedExpression:message:sourceCodeContext:")
    guard contextClass.instancesRespond(to: selector) else { return nil }
    let source = XCTSourceCodeContext(location: XCTSourceCodeLocation(filePath: file, lineNumber: line))
    // alloc's reference is the one the initializer consumes; it returns
    // its own.
    let allocated = contextClass.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
    let initialize = unsafeBitCast(contextClass.instanceMethod(for: selector), to: MakeContext.self)
    return initialize(allocated, selector, nil, nil, message as NSString?, source)?.takeRetainedValue()
}

public struct XCTSkip: Error, CustomNSError {
    /// The skipped-test context XCTest reads, or the message alone when
    /// the context can't be made.
    private let context: AnyObject?
    private let text: String?

    public var message: String? {
        if let context, let message = context.value(forKey: "message") as? String { return message }
        return text
    }

    public init(_ message: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        context = skippedTestContext(message: message, file: file, line: line)
        text = message
        errorCode = 106
    }

    public static let errorDomain: String = XCTestErrorDomain

    public let errorCode: Int

    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [shouldIgnoreKey: true]
        if let context { userInfo[skippedTestContextKey] = context }
        if let text { userInfo[NSLocalizedDescriptionKey] = text }
        return userInfo
    }
}

public func XCTSkipIf(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String? = nil,
                      file: StaticString = #filePath, line: UInt = #line) throws {
    if try expression() { throw XCTSkip(message(), file: file, line: line) }
}

public func XCTSkipUnless(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String? = nil,
                          file: StaticString = #filePath, line: UInt = #line) throws {
    if try !expression() { throw XCTSkip(message(), file: file, line: line) }
}
