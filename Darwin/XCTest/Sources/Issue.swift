import Foundation

// XCTIssue, the Swift value of XCTest's XCTIssue class (XCTIssueReference
// in Swift), and the expected failures that match issues.

public struct XCTIssue: Hashable {
    public typealias IssueType = XCTIssueReference.IssueType
    public typealias Severity = XCTIssueReference.Severity

    public var type: IssueType
    public var compactDescription: String
    public var detailedDescription: String?
    public var sourceCodeContext: XCTSourceCodeContext
    public var associatedError: (any Error)?
    public var attachments: [XCTAttachment]
    public var severity: Severity

    public init(type: IssueType, compactDescription: String, detailedDescription: String? = nil,
                sourceCodeContext: XCTSourceCodeContext = .init(), associatedError: (any Error)? = nil,
                attachments: [XCTAttachment] = [], severity: Severity = .error) {
        self.type = type
        self.compactDescription = compactDescription
        self.detailedDescription = detailedDescription
        self.sourceCodeContext = sourceCodeContext
        self.associatedError = associatedError
        self.attachments = attachments
        self.severity = severity
    }

    @_disfavoredOverload
    public init(type: IssueType, compactDescription: String, detailedDescription: String? = nil,
                sourceCodeContext: XCTSourceCodeContext = .init(), associatedError: (any Error)? = nil,
                attachments: [XCTAttachment] = []) {
        self.init(type: type, compactDescription: compactDescription, detailedDescription: detailedDescription,
                  sourceCodeContext: sourceCodeContext, associatedError: associatedError,
                  attachments: attachments, severity: .error)
    }

    /// Whether the issue fails the test: an error, not a warning.
    public var isFailure: Bool { severity >= .error }

    public mutating func add(_ attachment: XCTAttachment) {
        attachments.append(attachment)
    }

    public static func == (a: XCTIssue, b: XCTIssue) -> Bool {
        a.type == b.type && a.compactDescription == b.compactDescription
            && a.detailedDescription == b.detailedDescription && a.sourceCodeContext == b.sourceCodeContext
            && (a.associatedError as NSError?) == (b.associatedError as NSError?)
            && a.attachments == b.attachments && a.severity == b.severity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(compactDescription)
        hasher.combine(detailedDescription)
        hasher.combine(sourceCodeContext)
        hasher.combine(severity)
    }
}

extension XCTIssue: CustomStringConvertible {
    public var description: String {
        var text = compactDescription
        if let location = sourceCodeContext.location {
            text = "\(location.fileURL.path):\(location.lineNumber): \(text)"
        }
        if let detailedDescription, detailedDescription != compactDescription {
            text += "\n\(detailedDescription)"
        }
        return text
    }
}

extension XCTIssue: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = XCTIssueReference

    public func _bridgeToObjectiveC() -> XCTIssueReference {
        let issue = XCTMutableIssue(type: type, compactDescription: compactDescription,
                                    detailedDescription: detailedDescription, sourceCodeContext: sourceCodeContext,
                                    associatedError: associatedError, attachments: attachments)
        issue.severity = severity
        return issue
    }

    public static func _forceBridgeFromObjectiveC(_ source: XCTIssueReference, result: inout XCTIssue?) {
        result = _unconditionallyBridgeFromObjectiveC(source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: XCTIssueReference, result: inout XCTIssue?) -> Bool {
        result = _unconditionallyBridgeFromObjectiveC(source)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: XCTIssueReference?) -> XCTIssue {
        guard let source else { return XCTIssue(type: .system, compactDescription: "") }
        return XCTIssue(type: source.type, compactDescription: source.compactDescription,
                        detailedDescription: source.detailedDescription, sourceCodeContext: source.sourceCodeContext,
                        associatedError: source.associatedError, attachments: source.attachments,
                        severity: source.severity)
    }
}

extension XCTIssueReference.Severity: Comparable {
    public static func < (lhs: XCTIssueReference.Severity, rhs: XCTIssueReference.Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension XCTSourceCodeLocation {
    public convenience init(filePath: StaticString = #filePath, lineNumber: UInt = #line) {
        self.init(filePath: filePath.description, lineNumber: Int(lineNumber))
    }
}

// Expected failures.

extension XCTExpectedFailure.Options {
    @usableFromInline
    convenience init(enabled: Bool? = nil, strict: Bool? = nil, issueMatcher: ((XCTIssue) -> Bool)? = nil) {
        self.init()
        if let enabled { isEnabled = enabled }
        if let strict { isStrict = strict }
        if let issueMatcher { self.issueMatcher = issueMatcher }
    }
}

public func XCTExpectFailure(_ failureReason: String? = nil, options: XCTExpectedFailure.Options = .init()) {
    __XCTExpectFailureWithOptions(failureReason, options)
}

@inlinable
public func XCTExpectFailure(_ failureReason: String? = nil, enabled: Bool? = nil, strict: Bool? = nil,
                             issueMatcher: ((XCTIssue) -> Bool)? = nil) {
    let options = XCTExpectedFailure.Options(enabled: enabled, strict: strict, issueMatcher: issueMatcher)
    XCTExpectFailure(failureReason, options: options)
}

public func XCTExpectFailure<R>(_ failureReason: String? = nil, options: XCTExpectedFailure.Options = .init(),
                                failingBlock: () throws -> R) rethrows -> R {
    var result: Result<R, any Error>?
    return try withoutActuallyEscaping(failingBlock) { failingBlock in
        __XCTExpectFailureWithOptionsInBlock(failureReason, options) {
            result = Result { try failingBlock() }
        }
        return try result!.get()
    }
}

@inlinable
public func XCTExpectFailure<R>(_ failureReason: String? = nil, enabled: Bool? = nil, strict: Bool? = nil,
                                failingBlock: () throws -> R, issueMatcher: ((XCTIssue) -> Bool)? = nil) rethrows -> R {
    let options = XCTExpectedFailure.Options(enabled: enabled, strict: strict, issueMatcher: issueMatcher)
    return try XCTExpectFailure(failureReason, options: options, failingBlock: failingBlock)
}
