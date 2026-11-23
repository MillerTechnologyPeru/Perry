import Foundation

// The XCTAssert family: each evaluates its expressions, and on a failure,
// or an error thrown from them, records it on the test case running, the
// way the Objective-C macros of XCTestAssertions.h do, through XCTest's
// failure handler.

/// The test case running on this thread, which XCTest exports but no
/// header declares; returned unretained.
@_silgen_name("_XCTCurrentTestCase")
private func currentTestCaseObject() -> UnsafeRawPointer?

/// The test case running, if any.
func currentTestCase() -> XCTestCase? {
    guard let object = currentTestCaseObject() else { return nil }
    return Unmanaged<XCTestCase>.fromOpaque(object).takeUnretainedValue()
}

/// What an assertion does when it fails.
enum AssertionFailure {
    /// The values didn't pass: an expected failure, with what they were.
    case failed(String)
    /// An expression threw.
    case threw(any Error)
}

/// Records an assertion's failure on the current test case.
func record(_ assertion: String, _ failure: AssertionFailure, _ message: String, file: StaticString, line: UInt) {
    let condition: String
    let expected: Bool
    switch failure {
    case .failed(let detail):
        condition = detail.isEmpty ? "\(assertion) failed" : "\(assertion) failed: \(detail)"
        expected = true
    case .threw(let error):
        condition = "\(assertion) threw error \"\(error)\""
        expected = false
    }
    _XCTPreformattedFailureHandler(currentTestCase(), expected, file.description, Int(line), condition, message)
}

/// Runs an assertion's evaluation: what it returns is the failure, if any.
func evaluate(_ assertion: String, _ message: () -> String, file: StaticString, line: UInt,
              _ body: () throws -> String?) {
    let failure: AssertionFailure?
    do {
        failure = try body().map(AssertionFailure.failed)
    } catch {
        failure = .threw(error)
    }
    if let failure { record(assertion, failure, message(), file: file, line: line) }
}

/// How an assertion shows a value.
func show(_ value: Any?) -> String {
    guard let value else { return "nil" }
    return String(describing: value)
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record("", .failed(""), message, file: file, line: line)
}

public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    evaluate("XCTAssertNil", message, file: file, line: line) {
        let value = try expression()
        return value == nil ? nil : "\"\(show(value))\""
    }
}

public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    evaluate("XCTAssertNotNil", message, file: file, line: line) {
        try expression() == nil ? "" : nil
    }
}

/// What XCTUnwrap throws when the value is nil, which the test's run
/// records as a failure.
struct UnwrapError: CustomNSError, CustomStringConvertible {
    static var errorDomain: String { XCTestErrorDomain }
    var errorCode: Int { 105 }
    let message: String
    var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: description] }
    var description: String { message }
}

public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) throws -> T {
    let value: T?
    do {
        value = try expression()
    } catch {
        record("XCTUnwrap", .threw(error), message(), file: file, line: line)
        throw error
    }
    if let value { return value }
    let text = message()
    record("XCTUnwrap", .failed("expected non-nil value of type \"\(T.self)\""), text, file: file, line: line)
    throw UnwrapError(message: text.isEmpty ? "XCTUnwrap failed: expected non-nil value of type \"\(T.self)\""
                                            : "XCTUnwrap failed: expected non-nil value of type \"\(T.self)\" - \(text)")
}

public func XCTAssert(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
    evaluate("XCTAssertTrue", message, file: file, line: line) { try expression() ? nil : "" }
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    evaluate("XCTAssertTrue", message, file: file, line: line) { try expression() ? nil : "" }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    evaluate("XCTAssertFalse", message, file: file, line: line) { try expression() ? "" : nil }
}

/// Compares two values with `passes`, describing them with `relation`
/// when they don't.
func compare<T>(_ assertion: String, _ expression1: () throws -> T, _ expression2: () throws -> T,
                _ message: () -> String, file: StaticString, line: UInt,
                relation: String, passes: (T, T) -> Bool) {
    evaluate(assertion, message, file: file, line: line) {
        let first = try expression1(), second = try expression2()
        return passes(first, second) ? nil : "(\"\(show(first))\") \(relation) (\"\(show(second))\")"
    }
}

/// Compares two values within an accuracy.
func compare<T>(_ assertion: String, _ expression1: () throws -> T, _ expression2: () throws -> T, accuracy: T,
                _ message: () -> String, file: StaticString, line: UInt,
                relation: String, passes: (T, T) -> Bool) {
    evaluate(assertion, message, file: file, line: line) {
        let first = try expression1(), second = try expression2()
        return passes(first, second) ? nil
            : "(\"\(show(first))\") \(relation) (\"\(show(second))\") +/- (\"\(show(accuracy))\")"
    }
}

/// Whether two floating-point values are within `accuracy`: equal ones
/// are (infinities included), NaNs never are.
func within<T: FloatingPoint>(_ a: T, _ b: T, _ accuracy: T) -> Bool {
    a == b || (a - b).magnitude <= accuracy
}

/// Whether two numbers are within `accuracy`: integers by the difference
/// of the larger and the smaller, so unsigned ones don't overflow, other
/// numbers by their difference's magnitude.
func within<T: Numeric>(_ a: T, _ b: T, _ accuracy: T) -> Bool {
    if a == b { return true }
    if let a = a as? any BinaryInteger {
        func integers<I: BinaryInteger>(_ a: I) -> Bool {
            let b = b as! I, accuracy = accuracy as! I
            return (a > b ? a - b : b - a) <= accuracy
        }
        return integers(a)
    }
    return (a - b).magnitude <= accuracy.magnitude
}

public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "",
                                         file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertEqual", expression1, expression2, message, file: file, line: line,
            relation: "is not equal to", passes: ==)
}

public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                            _ message: @autoclosure () -> String = "",
                                            file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertNotEqual", expression1, expression2, message, file: file, line: line,
            relation: "is equal to", passes: !=)
}

public func XCTAssertEqual<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                             accuracy: T, _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertEqual", expression1, expression2, accuracy: accuracy, message, file: file, line: line,
            relation: "is not equal to") { within($0, $1, accuracy) }
}

public func XCTAssertEqual<T: Numeric>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                       accuracy: T, _ message: @autoclosure () -> String = "",
                                       file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertEqual", expression1, expression2, accuracy: accuracy, message, file: file, line: line,
            relation: "is not equal to") { within($0, $1, accuracy) }
}

@available(*, deprecated, renamed: "XCTAssertEqual(_:_:accuracy:file:line:)")
public func XCTAssertEqualWithAccuracy<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                         accuracy: T, _ message: @autoclosure () -> String = "",
                                                         file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertEqualWithAccuracy", expression1, expression2, accuracy: accuracy, message, file: file, line: line,
            relation: "is not equal to") { within($0, $1, accuracy) }
}

public func XCTAssertNotEqual<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                accuracy: T, _ message: @autoclosure () -> String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertNotEqual", expression1, expression2, accuracy: accuracy, message, file: file, line: line,
            relation: "is equal to") { !within($0, $1, accuracy) }
}

public func XCTAssertNotEqual<T: Numeric>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                          accuracy: T, _ message: @autoclosure () -> String = "",
                                          file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertNotEqual", expression1, expression2, accuracy: accuracy, message, file: file, line: line,
            relation: "is equal to") { !within($0, $1, accuracy) }
}

@available(*, deprecated, renamed: "XCTAssertNotEqual(_:_:accuracy:file:line:)")
public func XCTAssertNotEqualWithAccuracy<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                            _ accuracy: T, _ message: @autoclosure () -> String = "",
                                                            file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertNotEqualWithAccuracy", expression1, expression2, accuracy: accuracy, message, file: file, line: line,
            relation: "is equal to") { !within($0, $1, accuracy) }
}

public func XCTAssertIdentical(_ expression1: @autoclosure () throws -> AnyObject?, _ expression2: @autoclosure () throws -> AnyObject?,
                               _ message: @autoclosure () -> String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertIdentical", expression1, expression2, message, file: file, line: line,
            relation: "is not identical to", passes: ===)
}

public func XCTAssertNotIdentical(_ expression1: @autoclosure () throws -> AnyObject?, _ expression2: @autoclosure () throws -> AnyObject?,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertNotIdentical", expression1, expression2, message, file: file, line: line,
            relation: "is identical to", passes: !==)
}

public func XCTAssertGreaterThan<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                _ message: @autoclosure () -> String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertGreaterThan", expression1, expression2, message, file: file, line: line,
            relation: "is not greater than", passes: >)
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                       _ message: @autoclosure () -> String = "",
                                                       file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertGreaterThanOrEqual", expression1, expression2, message, file: file, line: line,
            relation: "is less than", passes: >=)
}

public func XCTAssertLessThan<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                             _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertLessThan", expression1, expression2, message, file: file, line: line,
            relation: "is not less than", passes: <)
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                    _ message: @autoclosure () -> String = "",
                                                    file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertLessThanOrEqual", expression1, expression2, message, file: file, line: line,
            relation: "is greater than", passes: <=)
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "",
                                    file: StaticString = #filePath, line: UInt = #line,
                                    _ errorHandler: (_ error: any Error) -> Void = { _ in }) {
    do {
        _ = try expression()
        record("XCTAssertThrowsError", .failed(""), message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
    } catch {
        record("XCTAssertNoThrow", .failed("threw error \"\(error)\""), message(), file: file, line: line)
    }
}
