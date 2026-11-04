import CPerryGeometry
import PerryObjCInterop

// CATransaction: the settings changes to layers are animated with, nested
// by -begin and -commit; outside them, an implicit transaction lasts the
// run loop's turn. A transaction's completion block runs once the
// animations added in it have finished, or when it ends if there are none.

@ObjCClass("CATransaction")
open class CATransaction: NSObject {
    struct Transaction {
        var values: [String: NSObject] = [:]
        var completion: ObjCBlock?
        /// When the last animation added in it ends.
        var end: Double = 0
    }

    nonisolated(unsafe) static var stack: [Transaction] = []
    /// The run loop turn's transaction, outside any explicit one.
    nonisolated(unsafe) static var implicit = Transaction()
    nonisolated(unsafe) private static var implicitEnds = false

    private static var current: Transaction {
        get { stack.last ?? implicit }
        set {
            if stack.isEmpty {
                implicit = newValue
                endImplicitSoon()
            } else {
                stack[stack.count - 1] = newValue
            }
        }
    }

    /// Ends the implicit transaction once the run loop's turn is done.
    private static func endImplicitSoon() {
        guard !implicitEnds else { return }
        implicitEnds = true
        Dispatch.onMain {
            implicitEnds = false
            let transaction = implicit
            implicit = Transaction()
            finish(transaction)
        }
    }

    /// Runs the completion block when the transaction's animations end.
    private static func finish(_ transaction: Transaction) {
        guard let completion = transaction.completion else { return }
        let wait = transaction.end - Clock.now
        if wait > 0 { Dispatch.onMain(after: wait) { Blocks.call(completion) } } else { Dispatch.onMain { Blocks.call(completion) } }
    }

    /// Notes an animation added to a layer in the current transaction.
    static func added(_ animation: CAAnimation) {
        let end = Presentation.end(of: animation)
        guard end.isFinite else { return }
        current.end = max(current.end, end)
    }

    @ObjCClassMethod("begin") static func begin() { stack.append(Transaction()) }

    @ObjCClassMethod("commit")
    static func commit() {
        guard let transaction = stack.popLast() else { return }
        // An enclosing transaction waits for these animations too.
        if !stack.isEmpty { stack[stack.count - 1].end = max(stack[stack.count - 1].end, transaction.end) }
        finish(transaction)
    }

    @ObjCClassMethod("flush") static func flush() {}
    @ObjCClassMethod("lock") static func lock() {}
    @ObjCClassMethod("unlock") static func unlock() {}

    @ObjCClassMethod("valueForKey:") static func value(forKey key: String) -> NSObject? { current.values[key] }
    @ObjCClassMethod("setValue:forKey:")
    static func setValue(_ value: NSObject?, forKey key: String) { current.values[key] = value }

    @ObjCClassMethod("disableActions")
    static func disableActions() -> Bool { (stack.last ?? implicit).values["disableActions"].map { $0.sendBoolValue() } ?? false }
    /// Core Animation's private switch to a background thread's context:
    /// transactions here are one tree's, whatever the thread.
    @ObjCClassMethod("activateBackground:")
    static func activateBackground(_ activate: Bool) {}

    @ObjCClassMethod("setDisableActions:")
    static func setDisableActions(_ disable: Bool) { current.values["disableActions"] = NSNumber.make(bool: disable) }

    @ObjCClassMethod("animationDuration")
    static func animationDuration() -> Double { (stack.last ?? implicit).values["animationDuration"].map { $0.sendDoubleValue() } ?? 0.25 }
    @ObjCClassMethod("setAnimationDuration:")
    static func setAnimationDuration(_ duration: Double) { current.values["animationDuration"] = NSNumber.make(double: duration) }

    @ObjCClassMethod("animationTimingFunction")
    static func animationTimingFunction() -> CAMediaTimingFunction? {
        (stack.last ?? implicit).values["animationTimingFunction"]?.as(CAMediaTimingFunction.self)
    }
    @ObjCClassMethod("setAnimationTimingFunction:")
    static func setAnimationTimingFunction(_ function: CAMediaTimingFunction?) { current.values["animationTimingFunction"] = function }

    @ObjCClassMethod("completionBlock") static func completionBlock() -> ObjCBlock? { (stack.last ?? implicit).completion }
    @ObjCClassMethod("setCompletionBlock:") static func setCompletionBlock(_ block: ObjCBlock?) { current.completion = block }
}

@ObjCConstants
enum TransactionConstants {
    static let kCATransactionDisableActions = "disableActions"
    static let kCATransactionAnimationDuration = "animationDuration"
    static let kCATransactionAnimationTimingFunction = "animationTimingFunction"
    static let kCATransactionCompletionBlock = "completionBlock"
}
