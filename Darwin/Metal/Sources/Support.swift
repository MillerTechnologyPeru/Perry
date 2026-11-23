import Foundation

extension NSRange {
    /// The NSRange Metal's Objective-C API takes for a Swift range.
    init(_ range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.count)
    }
}

extension Range where Bound == Int {
    /// The Swift range of an NSRange Metal's Objective-C API gives.
    init(_ range: NSRange) {
        self = range.location ..< range.location + range.length
    }
}

