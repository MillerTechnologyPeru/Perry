import CPerryGeometry
import PerryObjCInterop

// UIAlertView and UIPopoverController, which UIAlertController and
// popover presentation replaced, UIUserNotificationSettings, which
// UNUserNotificationCenter replaced, and CATransaction.

final class AlertViewState: ObjectState {
    var title: String?
    var message: String?
    var delegate: UnsafeMutableRawPointer?
    var buttons: [String] = []
    var cancelButtonIndex = -1
    var visible = false
    /// UIAlertViewStyle: default 0, secure text input 1, plain text input 2,
    /// login and password input 3.
    var style = 0
    var textFields: [UITextField] = []
    /// The dimmed view over the key window, while shown.
    var overlay: UIView?
}

/// An alert over the key window: its title, message, the text fields its
/// style has, and its buttons, side by side when there are two (cancel on
/// the left) and otherwise one above another (cancel last). A tap on a
/// button tells the delegate which, then dismisses the alert.
@ObjCClass("UIAlertView")
open class UIAlertView: UIView {
    static let alertStates = StateTable<AlertViewState>()
    var alert: AlertViewState { UIAlertView.alertStates[objcObject] }
    /// Alerts on screen, which UIKit keeps until they are dismissed.
    nonisolated(unsafe) static var showing: [UIAlertView] = []

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIAlertView.alertStates.remove(objcObject)
        super.dealloc()
    }

    /// The variadic other button titles are not read: Xamarin and most apps
    /// pass nil and add them with -addButtonWithTitle:.
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
    @ObjCMethod("setAlertViewStyle:")
    func setAlertViewStyle(_ style: Int) {
        alert.style = style
        let count = style == 3 ? 2 : style == 0 ? 0 : 1
        alert.textFields = (0..<count).map { index in
            let field = UITextField.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UITextField.self)
            field.setBorderStyle(1)
            field.setFont(UIFont.systemFont(size: 13))
            field.setSecureTextEntry(style == 1 || (style == 3 && index == 1))
            if style == 3 { field.setPlaceholder(index == 0 ? "Login" : "Password") }
            return field
        }
    }
    @ObjCMethod("cancelButtonIndex") func cancelButtonIndex() -> Int { alert.cancelButtonIndex }
    @ObjCMethod("setCancelButtonIndex:") func setCancelButtonIndex(_ index: Int) { alert.cancelButtonIndex = index }
    @ObjCMethod("firstOtherButtonIndex") func firstOtherButtonIndex() -> Int {
        alert.buttons.indices.first { $0 != alert.cancelButtonIndex } ?? -1
    }
    @ObjCMethod("numberOfButtons") func numberOfButtons() -> Int { alert.buttons.count }
    @ObjCMethod("isVisible") func isVisible() -> Bool { alert.visible }

    @ObjCMethod("textFieldAtIndex:")
    func textField(at index: Int) -> UITextField? {
        guard alert.textFields.indices.contains(index) else {
            uikitFatal("textFieldIndex (\(index)) is outside of the bounds of the array of text fields")
        }
        return alert.textFields[index]
    }

    @ObjCMethod("addButtonWithTitle:")
    func addButton(title: String?) -> Int {
        alert.buttons.append(title ?? "")
        return alert.buttons.count - 1
    }

    @ObjCMethod("buttonTitleAtIndex:")
    func buttonTitle(at index: Int) -> String? { alert.buttons.indices.contains(index) ? alert.buttons[index] : nil }

    private var alertDelegate: NSObject? { alert.delegate.map { NSObject($0) } }

    @ObjCMethod("show")
    func show() {
        guard !alert.visible, let windowObject = Windows.key ?? Windows.all.last else { return }
        let window = UIView.wrap(windowObject)
        let delegate = alertDelegate
        if let delegate, delegate.responds(to: "willPresentAlertView:") { delegate.sendWillPresentAlertView(self) }
        let overlay = makeOverlay(in: window.state.bounds)
        window.addSubview(overlay)
        alert.overlay = overlay
        alert.visible = true
        UIAlertView.showing.append(self)
        _ = alert.textFields.first?.sendBecomeFirstResponder()
        if let delegate, delegate.responds(to: "didPresentAlertView:") { delegate.sendDidPresentAlertView(self) }
        Display.markDirty()
    }

    private func makeOverlay(in bounds: CGRect) -> UIView {
        func view(_ frame: CGRect) -> UIView {
            UIView.objCClass.object.allocated().initializeView(frame: frame).unsafeCast(to: UIView.self)
        }
        let overlay = view(bounds)
        overlay.setBackgroundColor(UIColor.gray(0, 0.4))
        let width: CGFloat = 270
        let panel = view(.zero)
        panel.setBackgroundColor(UIColor.gray(0.97))
        panel.state.geometry.cornerRadius = 14
        panel.state.geometry.masksToBounds = true
        var y: CGFloat = 20
        for (text, bold) in [(alert.title, true), (alert.message, false)] {
            guard let text, !text.isEmpty else { continue }
            let font = bold ? UIFont.boldSystemFont(size: 17) : UIFont.systemFont(size: 13)
            for line in TextLayout.lines(text, font: font, width: width - 32) {
                let label = UILabel.objCClass.object.allocated().initializeView(frame: CGRect(x: 16, y: y, width: width - 32, height: font.lineHeight()))
                    .unsafeCast(to: UILabel.self)
                label.setText(line)
                label.setFont(font)
                label.setTextAlignment(1)
                panel.addSubview(label)
                y += font.lineHeight()
            }
            y += 4
        }
        for (index, field) in alert.textFields.enumerated() {
            y += index == 0 ? 12 : 0
            field.sendSetFrame(CGRect(x: 16, y: y, width: width - 32, height: 25))
            panel.addSubview(field)
            y += 25
        }
        y += 16
        // Two buttons side by side, cancel first; otherwise stacked, cancel last.
        var order = Array(alert.buttons.indices)
        if let cancel = order.firstIndex(of: alert.cancelButtonIndex) {
            order.remove(at: cancel)
            if alert.buttons.count == 2 { order.insert(alert.cancelButtonIndex, at: 0) } else { order.append(alert.cancelButtonIndex) }
        }
        func addButton(_ index: Int, _ frame: CGRect) {
            let button = UIButton.button(UIButton.objCClass, type: 1).unsafeCast(to: UIButton.self)
            button.sendSetFrame(frame)
            button.setTitle(alert.buttons[index], for: 0)
            let bold = index != alert.cancelButtonIndex && (alert.buttons.count == 1 || index == order.last)
            button.titleLabel().setFont(bold ? UIFont.boldSystemFont(size: 17) : UIFont.systemFont(size: 17))
            button.addTarget(self, action: ObjCSelector("_perryClicked:"), for: 1 << 6)
            button.setTag(index)
            panel.addSubview(button)
        }
        let separator = { (frame: CGRect) in
            let line = view(frame)
            line.setBackgroundColor(UIColor.separator())
            panel.addSubview(line)
        }
        if order.count == 2 {
            separator(CGRect(x: 0, y: y, width: width, height: Screen.pixel))
            separator(CGRect(x: width / 2, y: y, width: Screen.pixel, height: 44))
            addButton(order[0], CGRect(x: 0, y: y, width: width / 2, height: 44))
            addButton(order[1], CGRect(x: width / 2, y: y, width: width / 2, height: 44))
            y += 44
        } else {
            for index in order {
                separator(CGRect(x: 0, y: y, width: width, height: Screen.pixel))
                addButton(index, CGRect(x: 0, y: y, width: width, height: 44))
                y += 44
            }
        }
        panel.sendSetFrame(CGRect(x: (bounds.width - width) / 2, y: max(8, (bounds.height - y) / 2), width: width, height: y))
        overlay.addSubview(panel)
        return overlay
    }

    @ObjCMethod("_perryClicked:")
    func clicked(_ sender: UIButton) {
        let index = sender.state.tag
        if let delegate = alertDelegate, delegate.responds(to: "alertView:clickedButtonAtIndex:") {
            delegate.sendAlertView(self, clickedButtonAt: index)
        }
        dismiss(clickedButtonIndex: index, animated: true)
    }

    @ObjCMethod("dismissWithClickedButtonIndex:animated:")
    func dismiss(clickedButtonIndex index: Int, animated: Bool) {
        guard alert.visible else { return }
        let delegate = alertDelegate
        if let delegate, delegate.responds(to: "alertView:willDismissWithButtonIndex:") { delegate.sendAlertView(self, willDismissWithButtonIndex: index) }
        for field in alert.textFields { _ = field.sendResignFirstResponder() }
        alert.overlay?.removeFromSuperview()
        alert.overlay = nil
        alert.visible = false
        if let delegate, delegate.responds(to: "alertView:didDismissWithButtonIndex:") { delegate.sendAlertView(self, didDismissWithButtonIndex: index) }
        UIAlertView.showing.removeAll { $0.objcObject == objcObject }
        Display.markDirty()
    }
}

extension NSObject {
    @ObjCMethod("willPresentAlertView:") func sendWillPresentAlertView(_ alert: UIAlertView)
    @ObjCMethod("didPresentAlertView:") func sendDidPresentAlertView(_ alert: UIAlertView)
    @ObjCMethod("alertView:clickedButtonAtIndex:") func sendAlertView(_ alert: UIAlertView, clickedButtonAt index: Int)
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

final class UserNotificationSettingsState: ObjectState {
    var types: UInt = 0
    var categories: NSObject?
}

/// The kinds of notification an app asked to show: UIUserNotificationType
/// badge 1, sound 2, alert 4.
@ObjCClass("UIUserNotificationSettings")
open class UIUserNotificationSettings: NSObject {
    static let states = StateTable<UserNotificationSettingsState>()
    var settings: UserNotificationSettingsState { UIUserNotificationSettings.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIUserNotificationSettings.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIUserNotificationSettings.objCClass.pointer)
    }

    @ObjCClassMethod("settingsForTypes:categories:")
    static func settings(_ cls: ObjCClass, types: UInt, categories: NSObject?) -> NSObject {
        let settings = cls.object.newInstance().unsafeCast(to: UIUserNotificationSettings.self)
        settings.settings.types = types
        settings.settings.categories = categories
        return settings
    }

    @ObjCMethod("types") func types() -> UInt { settings.types }
    @ObjCMethod("categories") func categories() -> NSObject? { settings.categories }
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
