import CPerryGeometry
import PerryObjCInterop

// UIAlertView and UIPopoverController, which UIAlertController and
// popover presentation replaced, and CATransaction.

final class AlertViewState: ObjectState {
    var title: String?
    var message: String?
    var delegate: UnsafeMutableRawPointer?
    var buttons: [String] = []
    var cancelButtonIndex = -1
    var visible = false
    var style = 0
}

/// An alert that is not drawn: -show reports it, and it stays visible
/// until dismissed.
@ObjCClass("UIAlertView")
open class UIAlertView: UIView {
    static let alertStates = StateTable<AlertViewState>()
    var alert: AlertViewState { UIAlertView.alertStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIAlertView.alertStates.remove(objcObject)
        super.dealloc()
    }

    /// The variadic other button titles are not read: the first is passed
    /// in a register on Darwin only when it is the sole one, which cannot
    /// be told apart here, so only the cancel button is added.
    @ObjCMethod("initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitles:")
    func initialize(title: String?, message: String?, delegate: NSObject?, cancelButtonTitle: String?,
                    otherButtonTitles: NSObject?) -> Self {
        _ = initialize(frame: .zero)
        alert.title = title
        alert.message = message
        alert.delegate = delegate?.objcObject
        if let cancelButtonTitle {
            alert.cancelButtonIndex = 0
            alert.buttons.append(cancelButtonTitle)
        }
        return self
    }

    @ObjCMethod("title") func title() -> String? { alert.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { alert.title = title }
    @ObjCMethod("message") func message() -> String? { alert.message }
    @ObjCMethod("setMessage:") func setMessage(_ message: String?) { alert.message = message }
    @ObjCMethod("delegate") func delegate() -> NSObject? { alert.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { alert.delegate = delegate?.objcObject }
    @ObjCMethod("alertViewStyle") func alertViewStyle() -> Int { alert.style }
    @ObjCMethod("setAlertViewStyle:") func setAlertViewStyle(_ style: Int) { alert.style = style }
    @ObjCMethod("cancelButtonIndex") func cancelButtonIndex() -> Int { alert.cancelButtonIndex }
    @ObjCMethod("setCancelButtonIndex:") func setCancelButtonIndex(_ index: Int) { alert.cancelButtonIndex = index }
    @ObjCMethod("firstOtherButtonIndex") func firstOtherButtonIndex() -> Int { alert.cancelButtonIndex == 0 ? 1 : 0 }
    @ObjCMethod("numberOfButtons") func numberOfButtons() -> Int { alert.buttons.count }
    @ObjCMethod("isVisible") func isVisible() -> Bool { alert.visible }
    @ObjCMethod("textFieldAtIndex:") func textField(at index: Int) -> NSObject? { nil }

    @ObjCMethod("addButtonWithTitle:")
    func addButton(title: String?) -> Int {
        alert.buttons.append(title ?? "")
        return alert.buttons.count - 1
    }

    @ObjCMethod("buttonTitleAtIndex:")
    func buttonTitle(at index: Int) -> String? { alert.buttons.indices.contains(index) ? alert.buttons[index] : nil }

    @ObjCMethod("show")
    func show() {
        alert.visible = true
        uikitWarning("alert: \(alert.title ?? "")\(alert.message.map { " — " + $0 } ?? "") [\(alert.buttons.joined(separator: ", "))]")
    }

    @ObjCMethod("dismissWithClickedButtonIndex:animated:")
    func dismiss(clickedButtonIndex index: Int, animated: Bool) {
        alert.visible = false
        guard let delegateObject = alert.delegate else { return }
        let delegate = NSObject(delegateObject)
        if delegate.responds(to: "alertView:willDismissWithButtonIndex:") { delegate.sendAlertView(self, willDismissWithButtonIndex: index) }
        if delegate.responds(to: "alertView:didDismissWithButtonIndex:") { delegate.sendAlertView(self, didDismissWithButtonIndex: index) }
    }
}

extension NSObject {
    @ObjCMethod("alertView:willDismissWithButtonIndex:") func sendAlertView(_ alert: UIAlertView, willDismissWithButtonIndex index: Int)
    @ObjCMethod("alertView:didDismissWithButtonIndex:") func sendAlertView(_ alert: UIAlertView, didDismissWithButtonIndex index: Int)
}

final class PopoverState: ObjectState {
    var content: UIViewController?
    var delegate: UnsafeMutableRawPointer?
    var size = CGSize(width: 320, height: 480)
    var visible = false
}

/// A popover that is not shown: it keeps its content and size, and is
/// visible between presenting and dismissing.
@ObjCClass("UIPopoverController")
open class UIPopoverController: NSObject {
    static let states = StateTable<PopoverState>()
    var popover: PopoverState { UIPopoverController.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIPopoverController.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIPopoverController.objCClass.pointer)
    }

    @ObjCMethod("initWithContentViewController:")
    func initialize(contentViewController: UIViewController?) -> Self {
        popover.content = contentViewController
        return self
    }

    @ObjCMethod("contentViewController") func contentViewController() -> UIViewController? { popover.content }
    @ObjCMethod("setContentViewController:") func setContentViewController(_ controller: UIViewController?) { popover.content = controller }
    @ObjCMethod("setContentViewController:animated:")
    func setContentViewController(_ controller: UIViewController?, animated: Bool) { popover.content = controller }
    @ObjCMethod("delegate") func delegate() -> NSObject? { popover.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { popover.delegate = delegate?.objcObject }
    @ObjCMethod("popoverContentSize") func popoverContentSize() -> CGSize { popover.size }
    @ObjCMethod("setPopoverContentSize:") func setPopoverContentSize(_ size: CGSize) { popover.size = size }
    @ObjCMethod("setPopoverContentSize:animated:") func setPopoverContentSize(_ size: CGSize, animated: Bool) { popover.size = size }
    @ObjCMethod("isPopoverVisible") func isPopoverVisible() -> Bool { popover.visible }
    @ObjCMethod("popoverArrowDirection") func popoverArrowDirection() -> UInt { 0 }
    @ObjCMethod("passthroughViews") func passthroughViews() -> NSObject? { nil }
    @ObjCMethod("setPassthroughViews:") func setPassthroughViews(_ views: NSObject?) {}

    @ObjCMethod("presentPopoverFromRect:inView:permittedArrowDirections:animated:")
    func present(from rect: CGRect, in view: UIView?, permittedArrowDirections: UInt, animated: Bool) { popover.visible = true }

    @ObjCMethod("presentPopoverFromBarButtonItem:permittedArrowDirections:animated:")
    func present(from item: NSObject?, permittedArrowDirections: UInt, animated: Bool) { popover.visible = true }

    @ObjCMethod("dismissPopoverAnimated:") func dismissPopover(animated: Bool) { popover.visible = false }
}

/// CATransaction: layer changes take effect at once, so a transaction
/// keeps only its settings, and its completion block runs when the
/// outermost transaction commits.
@ObjCClass("CATransaction")
open class CATransaction: NSObject {
    struct Transaction {
        var values: [String: NSObject] = [:]
        var completion: ObjCBlock?
    }

    nonisolated(unsafe) static var stack: [Transaction] = []
    /// Settings outside any explicit transaction.
    nonisolated(unsafe) static var implicit = Transaction()

    private static var current: Transaction {
        get { stack.last ?? implicit }
        set { if stack.isEmpty { implicit = newValue } else { stack[stack.count - 1] = newValue } }
    }

    @ObjCClassMethod("begin") static func begin() { stack.append(Transaction()) }

    @ObjCClassMethod("commit")
    static func commit() {
        guard let transaction = stack.popLast() else { return }
        if let completion = transaction.completion {
            if stack.isEmpty { Blocks.call(completion) } else if current.completion == nil { current.completion = completion }
        }
    }

    @ObjCClassMethod("flush") static func flush() {}
    @ObjCClassMethod("lock") static func lock() {}
    @ObjCClassMethod("unlock") static func unlock() {}

    @ObjCClassMethod("valueForKey:") static func value(forKey key: String) -> NSObject? { current.values[key] }
    @ObjCClassMethod("setValue:forKey:")
    static func setValue(_ value: NSObject?, forKey key: String) { current.values[key] = value }

    @ObjCClassMethod("disableActions")
    static func disableActions() -> Bool { current.values["disableActions"].map { $0.transactionBoolValue() } ?? false }
    @ObjCClassMethod("setDisableActions:")
    static func setDisableActions(_ disable: Bool) { current.values["disableActions"] = NSNumber.make(bool: disable) }

    @ObjCClassMethod("animationDuration")
    static func animationDuration() -> Double { current.values["animationDuration"].map { $0.transactionDoubleValue() } ?? 0.25 }
    @ObjCClassMethod("setAnimationDuration:")
    static func setAnimationDuration(_ duration: Double) { current.values["animationDuration"] = NSNumber.make(double: duration) }

    @ObjCClassMethod("animationTimingFunction") static func animationTimingFunction() -> NSObject? { current.values["animationTimingFunction"] }
    @ObjCClassMethod("setAnimationTimingFunction:")
    static func setAnimationTimingFunction(_ function: NSObject?) { current.values["animationTimingFunction"] = function }

    @ObjCClassMethod("completionBlock") static func completionBlock() -> ObjCBlock? { current.completion }
    @ObjCClassMethod("setCompletionBlock:")
    static func setCompletionBlock(_ block: ObjCBlock?) {
        guard let block else { current.completion = nil; return }
        // Outside a transaction, the block runs once the current work is done.
        if stack.isEmpty { Updates.afterPass { Blocks.call(block) } } else { current.completion = block }
    }
}

extension NSObject {
    @ObjCMethod("boolValue") func transactionBoolValue() -> Bool
    @ObjCMethod("doubleValue") func transactionDoubleValue() -> Double
}
