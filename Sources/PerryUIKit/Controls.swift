import CPerryGeometry
import Glibc
import PerryObjCInterop

// Controls and the other classes apps reach for besides views: UIControl's
// targets and actions, driven by touches; UIButton; the search bar and text
// view, which show their text; constraints, kept for Auto Layout; the
// device, screen, pasteboard and menu; alerts; and Core Animation's
// animations, which apply at once.

// MARK: - UIControl

final class ControlState: ObjectState {
    var targets: [(target: UnsafeMutableRawPointer?, action: UnsafeRawPointer, events: UInt)] = []
    var enabled = true
    var selected = false
    var highlighted = false
    var tracking = false
    var contentHorizontalAlignment = 0
    var contentVerticalAlignment = 0
}

/// UIControlEvents: touch down 1, touch up inside 1 << 6, value changed
/// 1 << 12, primary action triggered 1 << 13.
@ObjCClass("UIControl")
open class UIControl: UIView {
    static let controlStates = StateTable<ControlState>()
    var control: ControlState { UIControl.controlStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIControl.controlStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        control.enabled = !decoded.bool("UIDisabled")
        control.selected = decoded.bool("UISelected")
        control.highlighted = decoded.bool("UIHighlighted")
        control.contentHorizontalAlignment = decoded.integer("UIContentHorizontalAlignment")
        control.contentVerticalAlignment = decoded.integer("UIContentVerticalAlignment")
        return self
    }

    @ObjCMethod("addTarget:action:forControlEvents:")
    func addTarget(_ target: NSObject?, action: ObjCSelector, for events: UInt) {
        control.targets.append((target?.objcObject, action.pointer, events))
    }

    @ObjCMethod("removeTarget:action:forControlEvents:")
    func removeTarget(_ target: NSObject?, action: ObjCSelector?, for events: UInt) {
        control.targets.removeAll { entry in
            (target == nil || entry.target == target?.objcObject) && (action == nil || entry.action == action?.pointer) && entry.events & events != 0
        }
    }

    @ObjCMethod("allTargets")
    func allTargets() -> NSObject {
        let set = NSMutableSet.empty()
        for entry in control.targets { if let target = entry.target { set.add(NSObject(target)) } }
        return set
    }

    @ObjCMethod("allControlEvents") func allControlEvents() -> UInt { control.targets.reduce(0) { $0 | $1.events } }

    /// The targets' actions for the events, as a nil target goes up the
    /// responder chain to the first that handles the action.
    @ObjCMethod("sendActionsForControlEvents:")
    func sendActions(for events: UInt) {
        for entry in control.targets where entry.events & events != 0 {
            sendAction(ObjCSelector(entry.action), to: entry.target.map { NSObject($0) }, for: nil)
        }
    }

    @ObjCMethod("sendAction:to:forEvent:")
    func sendAction(_ action: ObjCSelector, to target: NSObject?, for event: NSObject?) {
        var receiver = target
        if receiver == nil {
            var responder: NSObject? = self
            while let candidate = responder, !candidate.responds(to: action.name) { responder = candidate.sendNextResponder() }
            receiver = responder
        }
        guard let receiver else { return }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(receiver.objcObject, action.pointer, objcObject, event?.objcObject)
    }

    @ObjCMethod("isEnabled") func isEnabled() -> Bool { control.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { control.enabled = enabled; setNeedsDisplay() }
    @ObjCMethod("isSelected") func isSelected() -> Bool { control.selected }
    @ObjCMethod("setSelected:") func setSelected(_ selected: Bool) { control.selected = selected; setNeedsDisplay() }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { control.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ highlighted: Bool) { control.highlighted = highlighted; setNeedsDisplay() }
    @ObjCMethod("isTracking") func isTracking() -> Bool { control.tracking }
    @ObjCMethod("isTouchInside") func isTouchInside() -> Bool { control.tracking }

    /// UIControlState: normal 0, highlighted 1, disabled 2, selected 4.
    @ObjCMethod("state")
    func controlState() -> UInt {
        (control.highlighted ? 1 : 0) | (control.enabled ? 0 : 2) | (control.selected ? 4 : 0)
    }

    @ObjCMethod("contentHorizontalAlignment") func contentHorizontalAlignment() -> Int { control.contentHorizontalAlignment }
    @ObjCMethod("setContentHorizontalAlignment:") func setContentHorizontalAlignment(_ alignment: Int) { control.contentHorizontalAlignment = alignment }
    @ObjCMethod("contentVerticalAlignment") func contentVerticalAlignment() -> Int { control.contentVerticalAlignment }
    @ObjCMethod("setContentVerticalAlignment:") func setContentVerticalAlignment(_ alignment: Int) { control.contentVerticalAlignment = alignment }

    // Touches: highlighted while down; a release inside is touch up inside.

    @ObjCMethod("touchesBegan:withEvent:")
    func touchesBegan(_ touches: NSObject, with event: NSObject?) {
        guard control.enabled else { return }
        control.tracking = true
        sendHighlighted(true)
        sendActions(for: 1)
    }

    @ObjCMethod("touchesMoved:withEvent:") func touchesMoved(_ touches: NSObject, with event: NSObject?) {}

    @ObjCMethod("touchesEnded:withEvent:")
    func touchesEnded(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        control.tracking = false
        sendHighlighted(false)
        let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self)
        let inside = touch.map { state.bounds.insetBy(-16).contains($0.location(in: self)) } ?? true
        if inside { sendActions(for: 1 << 6 | 1 << 13) }
    }

    @ObjCMethod("touchesCancelled:withEvent:")
    func touchesCancelled(_ touches: NSObject, with event: NSObject?) {
        control.tracking = false
        sendHighlighted(false)
    }
}

extension NSObject {
    @ObjCMethod("setHighlighted:") func sendHighlighted(_ highlighted: Bool)
    @ObjCMethod("anyObject") func anyObject() -> NSObject?
}

extension NSSet {
    @ObjCMethod("anyObject") func anyElement() -> NSObject?
}

extension CGRect {
    func insetBy(_ amount: CGFloat) -> CGRect {
        CGRect(x: minX + amount, y: minY + amount, width: width - 2 * amount, height: height - 2 * amount)
    }
}

// MARK: - UIButton

final class ButtonContentState: ObjectState {
    var title: String?
    var titleColor: UIColor?
    var image: UIImage?
    var backgroundImage: UIImage?
}

/// A button's title and images for one state, as nibs keep them.
@ObjCClass("UIButtonContent")
open class UIButtonContent: NSObject {
    static let states = StateTable<ButtonContentState>()
    var state: ButtonContentState { UIButtonContent.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIButtonContent.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIButtonContent.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        state.title = decoded.string("UITitle") ?? decoded.object("UIAttributedTitle")?.sendString()
        state.titleColor = decoded.object("UITitleColor")?.as(UIColor.self)
        state.image = decoded.object("UIImage")?.as(UIImage.self)
        state.backgroundImage = decoded.object("UIBackgroundImage")?.as(UIImage.self)
        return self
    }
}

final class ButtonState: ObjectState {
    var type = 0
    var titles: [UInt: String] = [:]
    var titleColors: [UInt: UIColor] = [:]
    var images: [UInt: UIImage] = [:]
    var backgroundImages: [UInt: UIImage] = [:]
    var titleLabel: UILabel?
    var imageView: UIImageView?
    var contentEdgeInsets = UIEdgeInsets.zero
    var titleEdgeInsets = UIEdgeInsets.zero
    var imageEdgeInsets = UIEdgeInsets.zero
}

@ObjCClass("UIButton")
open class UIButton: UIControl {
    static let buttonStates = StateTable<ButtonState>()
    var button: ButtonState { UIButton.buttonStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIButton.buttonStates.remove(objcObject)
        super.dealloc()
    }

    /// UIButtonType: custom 0, system 1.
    @ObjCClassMethod("buttonWithType:")
    static func button(_ cls: ObjCClass, type: Int) -> NSObject {
        let button = cls.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIButton.self)
        button.button.type = type
        return button
    }

    @ObjCClassMethod("systemButtonWithImage:target:action:")
    static func systemButton(_ cls: ObjCClass, image: UIImage?, target: NSObject?, action: ObjCSelector?) -> NSObject {
        let button = UIButton.button(cls, type: 1).unsafeCast(to: UIButton.self)
        if let image { button.setImage(image, for: 0) }
        if let action { button.addTarget(target, action: action, for: 1 << 6) }
        return button
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        button.type = decoded.integer("UIButtonType")
        let contents = decoded.object("UIButtonStatefulContent")?.as(NSDictionary.self)
        for key in contents?.allKeys().elements ?? [] {
            guard let content = contents?.object(forKeyObject: key)?.as(UIButtonContent.self) else { continue }
            let state = UInt(bitPattern: key.sendIntegerValue())
            if let title = content.state.title { button.titles[state] = title }
            if let color = content.state.titleColor { button.titleColors[state] = color }
            if let image = content.state.image { button.images[state] = image }
            if let image = content.state.backgroundImage { button.backgroundImages[state] = image }
        }
        button.contentEdgeInsets = decoded.insets("UIContentEdgeInsets")
        if let font = decoded.object("UIFont")?.as(UIFont.self) { titleLabel().setFont(font) }
        update()
        return self
    }

    @ObjCMethod("buttonType") func buttonType() -> Int { button.type }

    @ObjCMethod("titleLabel")
    func titleLabel() -> UILabel {
        if let label = button.titleLabel { return label }
        let label = UILabel.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UILabel.self)
        label.setFont(UIFont.systemFont(size: 15))
        button.titleLabel = label
        addSubview(label)
        return label
    }

    /// iOS 2's: the title label's font.
    @ObjCMethod("font") func font() -> UIFont { titleLabel().fontObject() }
    @ObjCMethod("setFont:") func setFont(_ font: UIFont?) { titleLabel().setFont(font) }

    @ObjCMethod("imageView")
    func imageView() -> UIImageView {
        if let view = button.imageView { return view }
        let view = UIImageView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIImageView.self)
        button.imageView = view
        addSubview(view)
        return view
    }

    /// The value for the current state, else for normal.
    private func current<T>(_ values: [UInt: T]) -> T? { values[controlState()] ?? values[0] }

    @ObjCMethod("titleForState:") func title(for state: UInt) -> String? { button.titles[state] ?? button.titles[0] }
    @ObjCMethod("setTitle:forState:") func setTitle(_ title: String?, for state: UInt) { button.titles[state] = title; update() }
    @ObjCMethod("titleColorForState:") func titleColor(for state: UInt) -> UIColor? { button.titleColors[state] ?? button.titleColors[0] }
    @ObjCMethod("setTitleColor:forState:") func setTitleColor(_ color: UIColor?, for state: UInt) { button.titleColors[state] = color; update() }
    @ObjCMethod("imageForState:") func image(for state: UInt) -> UIImage? { button.images[state] ?? button.images[0] }
    @ObjCMethod("setImage:forState:") func setImage(_ image: UIImage?, for state: UInt) { button.images[state] = image; update() }
    @ObjCMethod("backgroundImageForState:") func backgroundImage(for state: UInt) -> UIImage? { button.backgroundImages[state] ?? button.backgroundImages[0] }
    @ObjCMethod("setBackgroundImage:forState:") func setBackgroundImage(_ image: UIImage?, for state: UInt) {
        button.backgroundImages[state] = image
        update()
    }
    @ObjCMethod("setAttributedTitle:forState:") func setAttributedTitle(_ title: NSObject?, for state: UInt) { setTitle(title?.sendString(), for: state) }
    @ObjCMethod("currentTitle") func currentTitle() -> String? { current(button.titles) }
    @ObjCMethod("currentTitleColor") func currentTitleColor() -> UIColor { current(button.titleColors) ?? defaultTitleColor }
    @ObjCMethod("currentImage") func currentImage() -> UIImage? { current(button.images) }
    @ObjCMethod("showsTouchWhenHighlighted") func showsTouchWhenHighlighted() -> Bool { false }
    @ObjCMethod("setShowsTouchWhenHighlighted:") func setShowsTouchWhenHighlighted(_ shows: Bool) {}
    @ObjCMethod("contentEdgeInsets") func contentEdgeInsets() -> UIEdgeInsets { button.contentEdgeInsets }
    @ObjCMethod("setContentEdgeInsets:") func setContentEdgeInsets(_ insets: UIEdgeInsets) { button.contentEdgeInsets = insets; setNeedsLayout() }
    @ObjCMethod("titleEdgeInsets") func titleEdgeInsets() -> UIEdgeInsets { button.titleEdgeInsets }
    @ObjCMethod("setTitleEdgeInsets:") func setTitleEdgeInsets(_ insets: UIEdgeInsets) { button.titleEdgeInsets = insets; setNeedsLayout() }
    @ObjCMethod("imageEdgeInsets") func imageEdgeInsets() -> UIEdgeInsets { button.imageEdgeInsets }
    @ObjCMethod("setImageEdgeInsets:") func setImageEdgeInsets(_ insets: UIEdgeInsets) { button.imageEdgeInsets = insets; setNeedsLayout() }

    /// A system button's title is in the tint color, a custom one's white.
    private var defaultTitleColor: UIColor { button.type == 0 ? UIColor.white() : tintColor() }

    @ObjCMethod("setHighlighted:")
    override func setHighlighted(_ highlighted: Bool) {
        control.highlighted = highlighted
        update()
    }

    @ObjCMethod("setEnabled:")
    override func setEnabled(_ enabled: Bool) {
        control.enabled = enabled
        update()
    }

    @ObjCMethod("setSelected:")
    override func setSelected(_ selected: Bool) {
        control.selected = selected
        update()
    }

    /// The title and image for the current state.
    private func update() {
        if let title = current(button.titles) {
            let label = titleLabel()
            label.setText(title)
            let color = current(button.titleColors) ?? defaultTitleColor
            label.setTextColor(control.enabled ? color : UIColor.systemGray())
            label.state.alpha = control.highlighted && button.type == 1 ? 0.3 : 1
        } else {
            button.titleLabel?.setText(nil)
        }
        if let image = current(button.images) {
            imageView().setImage(image)
        } else {
            button.imageView?.setImage(nil)
        }
        if let background = current(button.backgroundImages) {
            state.geometry.contents = background.state.cgImage.map { NSObject($0) }
        }
        setNeedsLayout()
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let title = current(button.titles).map { Text.size($0, font: titleLabel().font) } ?? .zero
        let image = current(button.images)?.state.size ?? .zero
        let insets = button.contentEdgeInsets
        return CGSize(width: title.width + image.width + insets.left + insets.right + (button.type == 1 ? 0 : 0),
                      height: max(title.height, image.height, 30) + insets.top + insets.bottom)
    }

    @ObjCMethod("intrinsicContentSize") func intrinsicButtonSize() -> CGSize { sizeThatFits(.zero) }

    /// The image then the title, centered together.
    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        let bounds = state.bounds.inset(by: button.contentEdgeInsets)
        let imageSize = button.imageView?.imageState.image?.state.size ?? .zero
        let titleSize = button.titleLabel?.label.text.map { Text.size($0, font: titleLabel().font) } ?? .zero
        let total = imageSize.width + titleSize.width
        var x: CGFloat
        switch control.contentHorizontalAlignment {
        case 1, 4: x = bounds.minX
        case 2, 5: x = bounds.maxX - total
        default: x = bounds.midX - total / 2
        }
        button.imageView?.sendSetFrame(CGRect(x: x, y: bounds.midY - imageSize.height / 2, width: imageSize.width, height: imageSize.height))
        x += imageSize.width
        button.titleLabel?.sendSetFrame(CGRect(x: x, y: bounds.midY - titleSize.height / 2, width: min(titleSize.width, bounds.maxX - x),
                                               height: titleSize.height))
    }
}

extension NSObject {
    @ObjCMethod("integerValue") func sendIntegerValue() -> Int
}

// MARK: - UISearchBar

final class SearchBarState: ObjectState {
    var text: String?
    var placeholder: String?
    var prompt: String?
    var delegate: UnsafeMutableRawPointer?
    var showsCancelButton = false
    var searchBarStyle = 0
    var barTintColor: UIColor?
    var scopeButtonTitles: NSObject?
    var selectedScopeButtonIndex = 0
    var showsScopeBar = false
    var field: UISearchTextField?
    var cancelButton: UIButton?
    /// The search controller whose bar this is, unretained.
    var controller: UnsafeMutableRawPointer?
}

/// A search field, and a Cancel button beside it while it shows one. What
/// is typed goes to the delegate and to the search controller's results
/// updater, as on iOS.
@ObjCClass("UISearchBar")
open class UISearchBar: UIView {
    static let searchStates = StateTable<SearchBarState>()
    var search: SearchBarState { UISearchBar.searchStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UISearchBar.searchStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        makeField()
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        search.text = decoded.string("UIText")
        search.placeholder = decoded.string("UIPlaceholder")
        search.prompt = decoded.string("UIPrompt")
        search.showsCancelButton = decoded.bool("UIShowsCancelButton")
        search.searchBarStyle = decoded.integer("UISearchBarStyle")
        makeField()
        return self
    }

    private func makeField() {
        guard search.field == nil else { return }
        let field = UISearchTextField.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UISearchTextField.self)
        field.setText(search.text)
        field.setPlaceholder(search.placeholder ?? "Search")
        field.setReturnKeyType(6)
        field.addTarget(self, action: ObjCSelector("_perrySearchBegan:"), for: 1 << 16)
        field.addTarget(self, action: ObjCSelector("_perrySearchChanged:"), for: 1 << 17)
        field.addTarget(self, action: ObjCSelector("_perrySearchEnded:"), for: 1 << 18)
        field.addTarget(self, action: ObjCSelector("_perrySearchReturn:"), for: 1 << 19)
        search.field = field
        addSubview(field)
        setNeedsLayout()
    }

    var field: UISearchTextField {
        makeField()
        return search.field!
    }

    var controller: UISearchController? { search.controller.map { NSObject($0).unsafeCast(to: UISearchController.self) } }
    private var barDelegate: NSObject? { search.delegate.map { NSObject($0) } }

    /// The bar's text field, by its private names too, which apps reach
    /// through key-value coding.
    @ObjCMethod("searchField") func searchField() -> UISearchTextField { field }
    @ObjCMethod("_searchField") func privateSearchField() -> UISearchTextField { field }
    @ObjCMethod("text") func text() -> String? { field.text() ?? "" }
    @ObjCMethod("setText:") func setText(_ text: String?) { search.text = text; field.setText(text) }
    @ObjCMethod("placeholder") func placeholder() -> String? { search.placeholder }
    @ObjCMethod("setPlaceholder:") func setPlaceholder(_ placeholder: String?) {
        search.placeholder = placeholder
        field.setPlaceholder(placeholder ?? "Search")
    }
    @ObjCMethod("prompt") func prompt() -> String? { search.prompt }
    @ObjCMethod("setPrompt:") func setPrompt(_ prompt: String?) { search.prompt = prompt }
    @ObjCMethod("delegate") func delegate() -> NSObject? { search.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { search.delegate = delegate?.objcObject }
    @ObjCMethod("showsCancelButton") func showsCancelButton() -> Bool { search.showsCancelButton }
    @ObjCMethod("setShowsCancelButton:") func setShowsCancelButton(_ shows: Bool) { search.showsCancelButton = shows; setNeedsLayout() }
    @ObjCMethod("setShowsCancelButton:animated:") func setShowsCancelButton(_ shows: Bool, animated: Bool) { setShowsCancelButton(shows) }
    @ObjCMethod("searchBarStyle") func searchBarStyle() -> Int { search.searchBarStyle }
    @ObjCMethod("setSearchBarStyle:") func setSearchBarStyle(_ style: Int) { search.searchBarStyle = style }
    @ObjCMethod("barTintColor") func barTintColor() -> UIColor? { search.barTintColor }
    @ObjCMethod("setBarTintColor:") func setBarTintColor(_ color: UIColor?) { search.barTintColor = color; setNeedsDisplay() }
    @ObjCMethod("scopeButtonTitles") func scopeButtonTitles() -> NSObject? { search.scopeButtonTitles }
    @ObjCMethod("setScopeButtonTitles:") func setScopeButtonTitles(_ titles: NSObject?) { search.scopeButtonTitles = titles }
    @ObjCMethod("selectedScopeButtonIndex") func selectedScopeButtonIndex() -> Int { search.selectedScopeButtonIndex }
    @ObjCMethod("setSelectedScopeButtonIndex:") func setSelectedScopeButtonIndex(_ index: Int) { search.selectedScopeButtonIndex = index }
    @ObjCMethod("showsScopeBar") func showsScopeBar() -> Bool { search.showsScopeBar }
    @ObjCMethod("setShowsScopeBar:") func setShowsScopeBar(_ shows: Bool) { search.showsScopeBar = shows }
    @ObjCMethod("searchTextField") func searchTextField() -> UISearchTextField { field }
    @ObjCMethod("keyboardType") func keyboardType() -> Int { field.keyboardType() }
    @ObjCMethod("setKeyboardType:") func setKeyboardType(_ type: Int) { field.setKeyboardType(type) }
    @ObjCMethod("returnKeyType") func returnKeyType() -> Int { field.returnKeyType() }
    @ObjCMethod("setReturnKeyType:") func setReturnKeyType(_ type: Int) { field.setReturnKeyType(type) }
    @ObjCMethod("autocapitalizationType") func autocapitalizationType() -> Int { field.autocapitalizationType() }
    @ObjCMethod("setAutocapitalizationType:") func setAutocapitalizationType(_ type: Int) { field.setAutocapitalizationType(type) }
    @ObjCMethod("autocorrectionType") func autocorrectionType() -> Int { field.autocorrectionType() }
    @ObjCMethod("setAutocorrectionType:") func setAutocorrectionType(_ type: Int) { field.setAutocorrectionType(type) }
    @ObjCMethod("inputAccessoryView") func inputAccessoryView() -> UIView? { field.inputAccessoryView() }
    @ObjCMethod("setInputAccessoryView:") func setInputAccessoryView(_ view: UIView?) { field.setInputAccessoryView(view) }

    @ObjCMethod("canBecomeFirstResponder") override func canBecomeFirstResponder() -> Bool { true }
    @ObjCMethod("isFirstResponder") override func isFirstResponder() -> Bool { Keyboard.isFirstResponder(field) }
    @ObjCMethod("becomeFirstResponder") override func becomeFirstResponder() -> Bool { field.sendBecomeFirstResponder() }
    @ObjCMethod("resignFirstResponder") override func resignFirstResponder() -> Bool { field.sendResignFirstResponder() }

    // MARK: Editing

    /// Asked of the delegate before the field begins editing.
    func shouldBeginEditing() -> Bool {
        guard let delegate = barDelegate, delegate.responds(to: "searchBarShouldBeginEditing:") else { return true }
        return delegate.sendSearchBarShouldBeginEditing(self)
    }

    @ObjCMethod("_perrySearchBegan:")
    func searchBegan(_ sender: NSObject?) {
        controller?.searchBarBeganEditing()
        if let delegate = barDelegate, delegate.responds(to: "searchBarTextDidBeginEditing:") { delegate.sendSearchBarTextDidBeginEditing(self) }
        setNeedsLayout()
    }

    @ObjCMethod("_perrySearchChanged:")
    func searchChanged(_ sender: NSObject?) {
        let text = field.text() ?? ""
        search.text = text
        if let delegate = barDelegate, delegate.responds(to: "searchBar:textDidChange:") { delegate.sendSearchBar(self, textDidChange: text) }
        controller?.searchBarChanged()
    }

    @ObjCMethod("_perrySearchEnded:")
    func searchEnded(_ sender: NSObject?) {
        if let delegate = barDelegate, delegate.responds(to: "searchBarTextDidEndEditing:") { delegate.sendSearchBarTextDidEndEditing(self) }
        setNeedsLayout()
    }

    @ObjCMethod("_perrySearchReturn:")
    func searchReturn(_ sender: NSObject?) {
        if let delegate = barDelegate, delegate.responds(to: "searchBarSearchButtonClicked:") { delegate.sendSearchBarSearchButtonClicked(self) }
    }

    /// Cancel: the delegate is told; a search controller's search ends,
    /// its text cleared and the keyboard put away.
    @ObjCMethod("_perrySearchCancel:")
    func searchCancel(_ sender: NSObject?) {
        if let delegate = barDelegate, delegate.responds(to: "searchBarCancelButtonClicked:") { delegate.sendSearchBarCancelButtonClicked(self) }
        if let controller {
            _ = field.sendResignFirstResponder()
            controller.setActive(false)
        }
        setNeedsLayout()
    }

    // MARK: Layout

    /// Cancel shows when asked for, or while a search controller's bar is
    /// in use.
    private var showsCancel: Bool {
        if search.showsCancelButton { return true }
        guard let controller, controller.searching.showsCancelButton else { return false }
        return controller.searching.active || Keyboard.isFirstResponder(field)
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width > 0 ? size.width : state.bounds.width, height: 56) }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = state.bounds
        var cancelWidth: CGFloat = 0
        if showsCancel {
            let button: UIButton
            if let existing = search.cancelButton {
                button = existing
            } else {
                button = UIButton.button(UIButton.objCClass, type: 1).unsafeCast(to: UIButton.self)
                button.setTitle("Cancel", for: 0)
                button.titleLabel().setFont(UIFont.systemFont(size: 17))
                button.addTarget(self, action: ObjCSelector("_perrySearchCancel:"), for: 1 << 6)
                search.cancelButton = button
                addSubview(button)
            }
            cancelWidth = Text.width("Cancel", font: UIFont.systemFont(size: 17)).rounded(.up) + 16
            button.setHidden(false)
            button.sendSetFrame(CGRect(x: bounds.width - cancelWidth - 4, y: bounds.midY - 18, width: cancelWidth, height: 36))
        } else {
            search.cancelButton?.setHidden(true)
        }
        field.sendSetFrame(CGRect(x: 8, y: bounds.midY - 18, width: max(bounds.width - 16 - (cancelWidth > 0 ? cancelWidth + 4 : 0), 0), height: 36))
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current, let tint = search.barTintColor else { return }
        withExtendedLifetime(tint) {
            CG.setFillColorWithColor(context, tint.state.makeCGColor())
            CG.fillRect(context, state.bounds)
        }
    }
}

/// A search bar's field: a rounded, tinted field with a magnifying glass
/// before its text.
@ObjCClass("UISearchTextField")
open class UISearchTextField: UITextField {
    var searchBar: UISearchBar? { superview()?.as(UISearchBar.self) }

    @ObjCMethod("becomeFirstResponder")
    override func becomeFirstResponder() -> Bool {
        if !Keyboard.isFirstResponder(self), let bar = searchBar, !bar.shouldBeginEditing() { return false }
        return super.becomeFirstResponder()
    }

    @ObjCMethod("textRectForBounds:")
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + 32, y: bounds.minY, width: max(bounds.width - 40, 0), height: bounds.height)
    }

    @ObjCMethod("intrinsicContentSize")
    override func intrinsicContentSize() -> CGSize { CGSize(width: -1, height: 36) }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let fill = UIColor.rgb(118.0 / 255, 118.0 / 255, 128.0 / 255, 0.12)
        withExtendedLifetime(fill) {
            CG.setFillColorWithColor(context, fill.state.makeCGColor())
            if let shape = roundedRectPath(bounds, radius: 10, corners: 0xf) {
                CG.addPath(context, shape.object)
                CG.fillPath(context)
            }
        }
        if let glass = Symbols.image(named: "magnifyingglass")?.withTintColor(UIColor.systemGray()) {
            let size = glass.state.size
            let height: CGFloat = 17
            let width = size.height > 0 ? size.width * height / size.height : height
            glass.draw(in: CGRect(x: 8, y: bounds.midY - height / 2, width: width, height: height))
        }
        super.draw(rect)
    }
}

extension NSObject {
    @ObjCMethod("searchBarShouldBeginEditing:") func sendSearchBarShouldBeginEditing(_ bar: UISearchBar) -> Bool
    @ObjCMethod("searchBarCancelButtonClicked:") func sendSearchBarCancelButtonClicked(_ bar: UISearchBar)
}

// MARK: - UITextView

final class TextViewState: ObjectState {
    var text = ""
    var font: UIFont?
    var textColor: UIColor?
    var textAlignment = 4
    var editable = true
    var selectable = true
    var delegate: UnsafeMutableRawPointer?
    var textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    var attributedText: NSObject?
    var dataDetectorTypes: UInt = 0
}

/// Text in a scroll view, wrapped to its width.
@ObjCClass("UITextView")
open class UITextView: UIScrollView {
    static let textStates = StateTable<TextViewState>()
    var textState: TextViewState { UITextView.textStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITextView.textStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let text = textState
        text.attributedText = decoded.object("UIAttributedText")
        text.text = decoded.string("UIText") ?? text.attributedText?.sendString() ?? ""
        text.font = decoded.object("UIFont")?.as(UIFont.self)
        text.textColor = decoded.object("UITextColor")?.as(UIColor.self)
        if decoded.has("UITextAlignment") { text.textAlignment = decoded.integer("UITextAlignment") }
        if decoded.has("UIEditable") { text.editable = decoded.bool("UIEditable") }
        if decoded.has("UISelectable") { text.selectable = decoded.bool("UISelectable") }
        return self
    }

    var font: UIFont { textState.font ?? UIFont.systemFont(size: 12) }

    @ObjCMethod("text") func text() -> String { textState.text }
    @ObjCMethod("setText:") func setText(_ text: String?) { textState.text = text ?? ""; textChanged() }
    @ObjCMethod("attributedText") func attributedText() -> NSObject? { textState.attributedText }
    @ObjCMethod("setAttributedText:") func setAttributedText(_ text: NSObject?) {
        textState.attributedText = text
        textState.text = text?.sendString() ?? ""
        textChanged()
    }
    @ObjCMethod("font") func fontObject() -> UIFont { font }
    @ObjCMethod("setFont:") func setFont(_ font: UIFont?) { textState.font = font; textChanged() }
    @ObjCMethod("textColor") func textColor() -> UIColor? { textState.textColor }
    @ObjCMethod("setTextColor:") func setTextColor(_ color: UIColor?) { textState.textColor = color; textChanged() }
    @ObjCMethod("textAlignment") func textAlignment() -> Int { textState.textAlignment }
    @ObjCMethod("setTextAlignment:") func setTextAlignment(_ alignment: Int) { textState.textAlignment = alignment; textChanged() }
    @ObjCMethod("isEditable") func isEditable() -> Bool { textState.editable }
    @ObjCMethod("setEditable:") func setEditable(_ editable: Bool) { textState.editable = editable }
    @ObjCMethod("isSelectable") func isSelectable() -> Bool { textState.selectable }
    @ObjCMethod("setSelectable:") func setSelectable(_ selectable: Bool) { textState.selectable = selectable }
    @ObjCMethod("textDelegate") func textDelegate() -> NSObject? { textState.delegate.map { NSObject($0) } }
    @ObjCMethod("textContainerInset") func textContainerInset() -> UIEdgeInsets { textState.textContainerInset }
    @ObjCMethod("setTextContainerInset:") func setTextContainerInset(_ inset: UIEdgeInsets) { textState.textContainerInset = inset; textChanged() }
    @ObjCMethod("scrollRangeToVisible:") func scrollRangeToVisible(_ range: PerryRange) {}
    @ObjCMethod("dataDetectorTypes") func dataDetectorTypes() -> UInt { textState.dataDetectorTypes }
    @ObjCMethod("setDataDetectorTypes:") func setDataDetectorTypes(_ types: UInt) { textState.dataDetectorTypes = types }

    /// The text is drawn by a view inside, sized to the wrapped text, so
    /// the content scrolls.
    private var textContent: UIView {
        if let view = state.subviews.first(where: { $0.is(UITextViewContent.self) }) { return view }
        let view = UITextViewContent.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIView.self)
        insertSubview(view, at: 0)
        return view
    }

    private func textChanged() {
        setNeedsLayout()
        textContent.setNeedsDisplay()
    }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textState.textContainerInset, width = state.bounds.width
        let lines = TextLayout.lines(textState.text, font: font, width: width - inset.left - inset.right - 10)
        let height = CGFloat(lines.count) * font.lineHeight() + inset.top + inset.bottom
        let content = textContent
        content.sendSetFrame(CGRect(x: 0, y: 0, width: width, height: height))
        content.setNeedsDisplay()
        scroll.contentSize = CGSize(width: width, height: height)
    }

    func drawText(in bounds: CGRect) {
        let inset = textState.textContainerInset
        let lines = TextLayout.lines(textState.text, font: font, width: bounds.width - inset.left - inset.right - 10)
        let color = textState.textColor ?? UIColor.label()
        for (index, line) in lines.enumerated() {
            let width = Text.size(line, font: font).width
            let x: CGFloat
            switch textState.textAlignment {
            case 1: x = bounds.midX - width / 2
            case 2: x = bounds.maxX - inset.right - 5 - width
            default: x = inset.left + 5
            }
            Text.draw(line, at: CGPoint(x: x, y: inset.top + CGFloat(index) * font.lineHeight()), font: font, color: color)
        }
    }
}

@ObjCClass("UITextViewContent")
open class UITextViewContent: UIView {
    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let textView = state.superview.map(UIView.wrap)?.as(UITextView.self) else { return }
        textView.drawText(in: state.bounds)
    }
}

/// Breaking text into lines that fit a width, at spaces and newlines.
enum TextLayout {
    static func lines(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        var lines: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = line.isEmpty ? String(word) : line + " " + word
                if !line.isEmpty, Text.width(candidate, font: font) > width {
                    lines.append(line)
                    line = String(word)
                } else {
                    line = candidate
                }
            }
            lines.append(line)
        }
        return lines
    }
}

// MARK: - NSLayoutConstraint

final class LayoutConstraintState: ObjectState {
    var firstItem: UnsafeMutableRawPointer?
    var secondItem: UnsafeMutableRawPointer?
    var firstAttribute = 0
    var secondAttribute = 0
    var relation = 0
    var multiplier: CGFloat = 1
    var constant: CGFloat = 0
    var priority: Float = 1000
    var active = false
    var identifier: String?
}

/// A constraint, which the view that holds it solves when it lays out its
/// subviews (AutoLayout).
@ObjCClass("NSLayoutConstraint")
open class NSLayoutConstraint: NSObject {
    static let states = StateTable<LayoutConstraintState>()
    var state: LayoutConstraintState { NSLayoutConstraint.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSLayoutConstraint.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSLayoutConstraint.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        let state = state
        state.firstItem = decoded.object("NSFirstItem")?.objcObject
        state.secondItem = decoded.object("NSSecondItem")?.objcObject
        // The V2 forms name margins where the others name edges with the
        // margins of Xcode's time added to the constant; a V2 constant
        // left out is zero.
        if decoded.has("NSFirstAttributeV2") {
            state.firstAttribute = decoded.integer("NSFirstAttributeV2")
            state.secondAttribute = decoded.integer("NSSecondAttributeV2")
            state.constant = decoded.double("NSConstantV2")
        } else {
            state.firstAttribute = decoded.integer("NSFirstAttribute")
            state.secondAttribute = decoded.integer("NSSecondAttribute")
            state.constant = decoded.double("NSConstant")
        }
        state.relation = decoded.integer("NSRelation")
        state.multiplier = decoded.has("NSMultiplier") ? decoded.double("NSMultiplier") : 1
        state.priority = decoded.has("NSPriority") ? Float(decoded.double("NSPriority")) : 1000
        state.identifier = decoded.string("NSLayoutIdentifier")
        state.active = true
        return self
    }

    @ObjCClassMethod("constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:")
    static func constraint(_ cls: ObjCClass, item: NSObject, attribute: Int, relatedBy relation: Int, toItem other: NSObject?,
                           attribute otherAttribute: Int, multiplier: CGFloat, constant: CGFloat) -> NSObject {
        let constraint = cls.object.allocated().unsafeCast(to: NSLayoutConstraint.self)
        let state = constraint.state
        (state.firstItem, state.firstAttribute, state.relation) = (item.objcObject, attribute, relation)
        (state.secondItem, state.secondAttribute, state.multiplier, state.constant) = (other?.objcObject, otherAttribute, multiplier, constant)
        return constraint
    }

    @ObjCClassMethod("constraintsWithVisualFormat:options:metrics:views:")
    static func constraints(visualFormat: String, options: UInt, metrics: NSObject?, views: NSObject?) -> NSObject { NSMutableArray.of([]) }

    /// Activating a constraint adds it to the views' closest common
    /// ancestor, as UIKit does; deactivating removes it.
    @ObjCClassMethod("activateConstraints:")
    static func activate(_ constraints: NSArray) {
        for constraint in constraints.elements { constraint.as(NSLayoutConstraint.self)?.setActive(true) }
    }

    @ObjCClassMethod("deactivateConstraints:")
    static func deactivate(_ constraints: NSArray) {
        for constraint in constraints.elements { constraint.as(NSLayoutConstraint.self)?.setActive(false) }
    }

    /// The closest view both items (or the views that own them, for
    /// guides) are in.
    private var holder: UIView? {
        guard let first = state.firstItem.flatMap({ LayoutItems.resolve($0)?.view }) else { return nil }
        guard let secondObject = state.secondItem else { return first }
        guard let second = LayoutItems.resolve(secondObject)?.view else { return first }
        var candidate: UIView? = first
        while let view = candidate {
            if view.objcObject == second.objcObject || second.isDescendant(of: view) { return view }
            candidate = view.state.superview.map { UIView.wrap($0) }
        }
        return nil
    }

    @ObjCMethod("firstItem") func firstItem() -> NSObject? { state.firstItem.map { NSObject($0) } }
    @ObjCMethod("secondItem") func secondItem() -> NSObject? { state.secondItem.map { NSObject($0) } }
    @ObjCMethod("firstAttribute") func firstAttribute() -> Int { state.firstAttribute }
    @ObjCMethod("secondAttribute") func secondAttribute() -> Int { state.secondAttribute }
    @ObjCMethod("relation") func relation() -> Int { state.relation }
    @ObjCMethod("multiplier") func multiplier() -> CGFloat { state.multiplier }
    @ObjCMethod("constant") func constant() -> CGFloat { state.constant }
    @ObjCMethod("setConstant:") func setConstant(_ constant: CGFloat) {
        state.constant = constant
        invalidate()
    }

    private func invalidate() {
        for item in [state.firstItem, state.secondItem].compactMap({ $0 }) {
            guard let view = LayoutItems.resolve(item)?.view else { continue }
            view.setNeedsLayout()
            view.superviewNeedsLayout()
        }
    }
    @ObjCMethod("priority") func priority() -> Float { state.priority }
    @ObjCMethod("setPriority:") func setPriority(_ priority: Float) { state.priority = priority }
    @ObjCMethod("isActive") func isActive() -> Bool { state.active }
    @ObjCMethod("setActive:")
    func setActive(_ active: Bool) {
        state.active = active
        if active, let holder, !holder.state.constraints.contains(where: { $0.objcObject == objcObject }) {
            holder.state.constraints.append(self)
        }
        invalidate()
    }
    @ObjCMethod("identifier") func identifier() -> String? { state.identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ identifier: String?) { state.identifier = identifier }
    @ObjCMethod("shouldBeArchived") func shouldBeArchived() -> Bool { true }
}

// MARK: - The device, screen, pasteboard and menu

/// An iPhone running iOS 15.
@ObjCClass("UIDevice")
open class UIDevice: NSObject {
    nonisolated(unsafe) static var current: UIDevice?

    @ObjCClassMethod("currentDevice")
    static func currentDevice() -> UIDevice {
        if let current { return current }
        let device = objCClass.object.allocated().unsafeCast(to: UIDevice.self)
        current = device
        return device
    }

    @ObjCMethod("name") func name() -> String { "iPhone" }
    @ObjCMethod("model") func model() -> String { "iPhone" }
    @ObjCMethod("localizedModel") func localizedModel() -> String { "iPhone" }
    @ObjCMethod("systemName") func systemName() -> String { "iOS" }
    /// The Taptic Engine a device has, by a key programs read with
    /// valueForKey: (0 none, 1 the first, 2 the second): none.
    @ObjCMethod("_feedbackSupportLevel") func feedbackSupportLevel() -> Int { 0 }

    /// The iOS version the app was built for, as NSProcessInfo gives it:
    /// the platform version in its Info.plist, or iOS 18 without one.
    @ObjCMethod("systemVersion")
    func systemVersion() -> String {
        // PERRY_OS_VERSION, else the version the app was built for.
        if let setting = getenv("PERRY_OS_VERSION") { return String(cString: setting) }
        return NSBundle.main().infoObject(forKey: "DTPlatformVersion")?.stringValue ?? "18.0"
    }
    /// UIUserInterfaceIdiom: phone 0.
    @ObjCMethod("userInterfaceIdiom") func userInterfaceIdiom() -> Int { 0 }
    /// UIDeviceOrientation: portrait 1.
    /// UIDeviceOrientation, which numbers landscape as the interface does.
    @ObjCMethod("orientation") func orientation() -> Int { Screen.orientation }
    @ObjCMethod("isMultitaskingSupported") func isMultitaskingSupported() -> Bool { true }
    @ObjCMethod("identifierForVendor") func identifierForVendor() -> NSObject { NSUUID.make() }
    /// The device's identifier of iOS 2 to 5, forty hexadecimal digits: the
    /// same for every app and every run, and no real device's.
    @ObjCMethod("uniqueIdentifier") func uniqueIdentifier() -> String { "7065727279000000000000000000000000000001" }
    /// Whether the battery is reported, as on iOS only once asked for.
    nonisolated(unsafe) static var batteryMonitoring = false
    @ObjCMethod("isBatteryMonitoringEnabled") func isBatteryMonitoringEnabled() -> Bool { UIDevice.batteryMonitoring }
    @ObjCMethod("setBatteryMonitoringEnabled:") func setBatteryMonitoringEnabled(_ enabled: Bool) { UIDevice.batteryMonitoring = enabled }

    /// The charge left, from 0 to 1, of the machine's battery; -1 while
    /// monitoring is off or there is none.
    @ObjCMethod("batteryLevel")
    func batteryLevel() -> Float {
        guard UIDevice.batteryMonitoring, let battery = PowerSupply.battery,
              let capacity = PowerSupply.read(battery, "capacity").flatMap(Float.init) else { return -1 }
        return min(max(capacity / 100, 0), 1)
    }

    /// UIDeviceBatteryState: unknown 0, unplugged 1, charging 2, full 3.
    @ObjCMethod("batteryState")
    func batteryState() -> Int {
        guard UIDevice.batteryMonitoring, let battery = PowerSupply.battery else { return 0 }
        switch PowerSupply.read(battery, "status") {
        case "Charging": return 2
        case "Full": return 3
        case "Discharging", "Not charging": return 1
        default: return 0
        }
    }
    @ObjCMethod("isProximityMonitoringEnabled") func isProximityMonitoringEnabled() -> Bool { false }
    @ObjCMethod("setProximityMonitoringEnabled:") func setProximityMonitoringEnabled(_ enabled: Bool) {}
    /// How many more times the notifications were begun than ended.
    nonisolated(unsafe) static var orientationObservers = 0

    @ObjCMethod("isGeneratingDeviceOrientationNotifications")
    func isGeneratingDeviceOrientationNotifications() -> Bool { UIDevice.orientationObservers > 0 }

    /// The device never turns, but the first notification comes all the
    /// same, a moment after they are first begun, as it does on a device
    /// once its accelerometer has answered: apps wait for it to learn which
    /// way they are held.
    @ObjCMethod("beginGeneratingDeviceOrientationNotifications")
    func beginGeneratingDeviceOrientationNotifications() {
        UIDevice.orientationObservers += 1
        guard UIDevice.orientationObservers == 1, let after = Display.dispatchAfter, let time = Display.dispatchTime else { return }
        after(time(0, 100_000_000), Updates.mainQueue, nil) { _ in
            guard UIDevice.orientationObservers > 0 else { return }
            Application.post(MoreNotifications.UIDeviceOrientationDidChangeNotification, object: UIDevice.currentDevice())
        }
    }

    @ObjCMethod("endGeneratingDeviceOrientationNotifications")
    func endGeneratingDeviceOrientationNotifications() { UIDevice.orientationObservers = max(UIDevice.orientationObservers - 1, 0) }
    @ObjCMethod("playInputClick") func playInputClick() {}
}

/// A screen's resolution, in pixels, with square pixels.
@ObjCClass("UIScreenMode")
open class UIScreenMode: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    nonisolated(unsafe) static let native = UIScreenMode()

    @ObjCMethod("size")
    func size() -> CGSize {
        let size = Screen.bounds.size
        return CGSize(width: min(size.width, size.height) * Screen.scale, height: max(size.width, size.height) * Screen.scale)
    }
    @ObjCMethod("pixelAspectRatio") func pixelAspectRatio() -> CGFloat { 1 }
}

/// The screen: the size and scale the views are laid out for.
@ObjCClass("UIScreen")
open class UIScreen: NSObject {
    nonisolated(unsafe) static var main: UIScreen?

    @ObjCClassMethod("mainScreen")
    static func mainScreen() -> UIScreen {
        if let main { return main }
        let screen = objCClass.object.allocated().unsafeCast(to: UIScreen.self)
        main = screen
        return screen
    }

    @ObjCClassMethod("screens") static func screens() -> NSObject { NSMutableArray.of([mainScreen()]) }

    @ObjCMethod("bounds") func bounds() -> CGRect { Screen.bounds }
    /// The panel's pixels, which stay in portrait as the interface turns.
    @ObjCMethod("nativeBounds") func nativeBounds() -> CGRect {
        let size = Screen.bounds.size
        return CGRect(x: 0, y: 0, width: min(size.width, size.height) * Screen.scale, height: max(size.width, size.height) * Screen.scale)
    }
    /// The one mode: the panel's pixels, as nativeBounds gives them.
    @ObjCMethod("currentMode") func currentMode() -> UIScreenMode { UIScreenMode.native }
    @ObjCMethod("preferredMode") func preferredMode() -> UIScreenMode { UIScreenMode.native }
    @ObjCMethod("availableModes") func availableModes() -> NSObject { NSMutableArray.of([UIScreenMode.native]) }
    @ObjCMethod("setCurrentMode:") func setCurrentMode(_ mode: NSObject?) {}
    @ObjCMethod("mirroredScreen") func mirroredScreen() -> NSObject? { nil }
    @ObjCMethod("isCaptured") func isCaptured() -> Bool { false }
    @ObjCMethod("overscanCompensation") func overscanCompensation() -> Int { 0 }
    @ObjCMethod("setOverscanCompensation:") func setOverscanCompensation(_ value: Int) {}
    @ObjCMethod("applicationFrame") func applicationFrame() -> CGRect { Screen.bounds }
    @ObjCMethod("scale") func scale() -> CGFloat { Screen.scale }
    @ObjCMethod("nativeScale") func nativeScale() -> CGFloat { Screen.scale }
    @ObjCMethod("brightness") func brightness() -> CGFloat { 0.5 }
    @ObjCMethod("setBrightness:") func setBrightness(_ brightness: CGFloat) {}
    @ObjCMethod("maximumFramesPerSecond") func maximumFramesPerSecond() -> Int { 60 }
    @ObjCMethod("coordinateSpace") func coordinateSpace() -> NSObject? { Windows.key.map { NSObject($0) } }
    @ObjCMethod("fixedCoordinateSpace") func fixedCoordinateSpace() -> NSObject { UIScreenFixedSpace.shared }

    /// A display link for this screen, the only one.
    @ObjCMethod("displayLinkWithTarget:selector:")
    func displayLink(target: NSObject, selector: ObjCSelector) -> CADisplayLink {
        CADisplayLink.make(target: target, selector: selector)
    }
    @ObjCMethod("traitCollection") func traitCollection() -> UITraitCollection { UITraitCollection.device() }
}

final class PasteboardState: ObjectState {
    var name = "com.apple.UIKit.pboard.general"
    var items: [String: NSObject] = [:]
}

/// The general pasteboard, within the process.
@ObjCClass("UIPasteboard")
open class UIPasteboard: NSObject {
    static let states = StateTable<PasteboardState>()
    var state: PasteboardState { UIPasteboard.states[objcObject] }
    nonisolated(unsafe) static var general: UIPasteboard?

    @ObjCClassMethod("generalPasteboard")
    static func generalPasteboard() -> UIPasteboard {
        if let general { return general }
        let pasteboard = objCClass.object.allocated().unsafeCast(to: UIPasteboard.self)
        general = pasteboard
        return pasteboard
    }

    /// Named pasteboards, kept for the life of the process; apps share
    /// data through them only with themselves here.
    nonisolated(unsafe) static var named: [String: UIPasteboard] = [:]

    @ObjCClassMethod("pasteboardWithName:create:")
    static func pasteboard(name: String, create: Bool) -> UIPasteboard? {
        if let pasteboard = named[name] { return pasteboard }
        guard create else { return nil }
        let pasteboard = objCClass.object.allocated().unsafeCast(to: UIPasteboard.self)
        pasteboard.state.name = name
        named[name] = pasteboard
        return pasteboard
    }

    @ObjCClassMethod("pasteboardWithUniqueName")
    static func pasteboardWithUniqueName() -> UIPasteboard? {
        pasteboard(name: "com.apple.UIKit.pboard.\(named.count + 1)", create: true)
    }

    @ObjCClassMethod("removePasteboardWithName:") static func removePasteboard(name: String) { named[name] = nil }

    @ObjCMethod("name") func name() -> String { state.name }
    @ObjCMethod("isPersistent") func isPersistent() -> Bool { false }
    @ObjCMethod("setPersistent:") func setPersistent(_ persistent: Bool) {}

    @ObjCMethod("string") func string() -> String? { state.items["public.utf8-plain-text"]?.stringValue }
    @ObjCMethod("setString:") func setString(_ string: String?) {
        state.items = string.map { ["public.utf8-plain-text": NSObject.nibString($0, mutable: false)] } ?? [:]
    }
    @ObjCMethod("URL") func url() -> NSObject? { state.items["public.url"] }
    @ObjCMethod("setURL:") func setURL(_ url: NSObject?) { state.items = url.map { ["public.url": $0] } ?? [:] }
    @ObjCMethod("image") func image() -> UIImage? { state.items["public.png"]?.as(UIImage.self) }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { state.items = image.map { ["public.png": $0] } ?? [:] }
    @ObjCMethod("hasStrings") func hasStrings() -> Bool { state.items["public.utf8-plain-text"] != nil }
    @ObjCMethod("hasURLs") func hasURLs() -> Bool { state.items["public.url"] != nil }
    @ObjCMethod("hasImages") func hasImages() -> Bool { state.items["public.png"] != nil }
    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { state.items.isEmpty ? 0 : 1 }
    @ObjCMethod("changeCount") func changeCount() -> Int { 0 }
    @ObjCMethod("setValue:forPasteboardType:") func setValue(_ value: NSObject?, forPasteboardType type: String) {
        state.items = value.map { [type: $0] } ?? [:]
    }
    @ObjCMethod("valueForPasteboardType:") func value(forPasteboardType type: String) -> NSObject? { state.items[type] }
    /// Data is kept as any other value is.
    @ObjCMethod("setData:forPasteboardType:") func setData(_ data: NSObject?, forPasteboardType type: String) {
        setValue(data, forPasteboardType: type)
    }
    @ObjCMethod("dataForPasteboardType:") func data(forPasteboardType type: String) -> NSObject? { state.items[type] }
    @ObjCMethod("pasteboardTypes") func pasteboardTypes() -> NSObject {
        NSMutableArray.of(state.items.keys.sorted().map { NSObject.nibString($0, mutable: false) })
    }
    @ObjCMethod("containsPasteboardTypes:") func contains(pasteboardTypes types: NSObject?) -> Bool {
        types?.as(NSArray.self)?.elements.contains { state.items[$0.stringValue] != nil } ?? false
    }
}

/// A screen's fixed coordinate space: the screen as held upright, its
/// short side across. Points are converted as they are: the display is
/// not turned from how the screen is drawn.
@ObjCClass("_UIScreenFixedCoordinateSpace")
open class UIScreenFixedSpace: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    nonisolated(unsafe) static let shared = UIScreenFixedSpace()

    @ObjCMethod("bounds")
    func bounds() -> CGRect {
        let size = Screen.bounds.size
        return CGRect(x: 0, y: 0, width: min(size.width, size.height), height: max(size.width, size.height))
    }

    @ObjCMethod("convertPoint:toCoordinateSpace:") func convert(_ point: CGPoint, to space: NSObject?) -> CGPoint { point }
    @ObjCMethod("convertPoint:fromCoordinateSpace:") func convert(_ point: CGPoint, from space: NSObject?) -> CGPoint { point }
    @ObjCMethod("convertRect:toCoordinateSpace:") func convert(_ rect: CGRect, to space: NSObject?) -> CGRect { rect }
    @ObjCMethod("convertRect:fromCoordinateSpace:") func convert(_ rect: CGRect, from space: NSObject?) -> CGRect { rect }
}

/// The edit menu, which is not shown.
@ObjCClass("UIMenuController")
open class UIMenuController: NSObject {
    nonisolated(unsafe) static var shared: UIMenuController?

    @ObjCClassMethod("sharedMenuController")
    static func sharedMenuController() -> UIMenuController {
        if let shared { return shared }
        let menu = objCClass.object.allocated().unsafeCast(to: UIMenuController.self)
        shared = menu
        return menu
    }

    @ObjCMethod("isMenuVisible") func isMenuVisible() -> Bool { false }
    @ObjCMethod("setMenuVisible:") func setMenuVisible(_ visible: Bool) {}
    @ObjCMethod("setMenuVisible:animated:") func setMenuVisible(_ visible: Bool, animated: Bool) {}
    @ObjCMethod("setTargetRect:inView:") func setTargetRect(_ rect: CGRect, in view: UIView?) {}
    @ObjCMethod("showMenuFromView:rect:") func showMenu(from view: UIView?, rect: CGRect) {}
    @ObjCMethod("hideMenu") func hideMenu() {}
    @ObjCMethod("menuItems") func menuItems() -> NSObject? { nil }
    @ObjCMethod("setMenuItems:") func setMenuItems(_ items: NSObject?) {}
    @ObjCMethod("update") func update() {}
}

// MARK: - Alerts

final class AlertActionState: ObjectState {
    var title: String?
    var style = 0
    var handler: ObjCBlock?
    var enabled = true
}

@ObjCClass("UIAlertAction")
open class UIAlertAction: NSObject {
    static let states = StateTable<AlertActionState>()
    var state: AlertActionState { UIAlertAction.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIAlertAction.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIAlertAction.objCClass.pointer)
    }

    /// UIAlertActionStyle: default 0, cancel 1, destructive 2.
    @ObjCClassMethod("actionWithTitle:style:handler:")
    static func action(_ cls: ObjCClass, title: String?, style: Int, handler: ObjCBlock?) -> NSObject {
        let action = cls.object.allocated().unsafeCast(to: UIAlertAction.self)
        (action.state.title, action.state.style, action.state.handler) = (title, style, handler)
        return action
    }

    @ObjCMethod("title") func title() -> String? { state.title }
    @ObjCMethod("style") func style() -> Int { state.style }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { state.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { state.enabled = enabled }
}

final class AlertState: ObjectState {
    var message: String?
    var style = 0
    var actions: [UIAlertAction] = []
    var preferredAction: UIAlertAction?
    var textFields: [NSObject] = []
}

/// An alert: its title, message and a button for each action, centered over
/// a dimmed screen. Choosing an action dismisses the alert, then calls its
/// handler.
@ObjCClass("UIAlertController")
open class UIAlertController: UIViewController {
    static let alertStates = StateTable<AlertState>()
    var alert: AlertState { UIAlertController.alertStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIAlertController.alertStates.remove(objcObject)
        super.dealloc()
    }

    /// UIAlertControllerStyle: action sheet 0, alert 1.
    @ObjCClassMethod("alertControllerWithTitle:message:preferredStyle:")
    static func alert(_ cls: ObjCClass, title: String?, message: String?, preferredStyle style: Int) -> NSObject {
        let alert = cls.object.allocated().initializeViewController(nibName: nil, bundle: nil).unsafeCast(to: UIAlertController.self)
        alert.state.title = title
        alert.alert.message = message
        alert.alert.style = style
        alert.state.modalPresentationStyle = 5
        // An alert is often an app's report of what went wrong.
        uikitWarning("alert: \(title ?? ""): \(message ?? "")")
        return alert
    }

    @ObjCMethod("message") func message() -> String? { alert.message }
    @ObjCMethod("setMessage:") func setMessage(_ message: String?) { alert.message = message }
    @ObjCMethod("preferredStyle") func preferredStyle() -> Int { alert.style }
    @ObjCMethod("actions") func actions() -> NSObject { NSMutableArray.of(alert.actions) }
    @ObjCMethod("addAction:") func addAction(_ action: UIAlertAction) { alert.actions.append(action) }
    @ObjCMethod("preferredAction") func preferredAction() -> UIAlertAction? { alert.preferredAction }
    @ObjCMethod("setPreferredAction:") func setPreferredAction(_ action: UIAlertAction?) { alert.preferredAction = action }
    @ObjCMethod("textFields") func textFields() -> NSObject? { alert.textFields.isEmpty ? nil : NSMutableArray.of(alert.textFields) }
    @ObjCMethod("addTextFieldWithConfigurationHandler:") func addTextField(configurationHandler: ObjCBlock?) {}

    @ObjCMethod("loadView")
    override func loadView() {
        let view = UIView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
        view.setBackgroundColor(UIColor.gray(0, 0.4))
        if alert.style == 0 {
            loadSheet(in: view)
            setView(view)
            return
        }
        let width: CGFloat = 270
        let panel = UIView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIView.self)
        panel.setBackgroundColor(UIColor.gray(0.97))
        panel.state.geometry.cornerRadius = 14
        panel.state.geometry.masksToBounds = true
        var y: CGFloat = 20
        for (text, bold) in [(state.title, true), (alert.message, false)] {
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
        y += 16
        func separator(_ frame: CGRect) {
            let line = UIView.objCClass.object.allocated().initializeView(frame: frame).unsafeCast(to: UIView.self)
            line.setBackgroundColor(UIColor.separator())
            panel.addSubview(line)
        }
        func addButton(_ action: UIAlertAction, _ frame: CGRect) {
            let button = UIButton.button(UIButton.objCClass, type: 1).unsafeCast(to: UIButton.self)
            button.sendSetFrame(frame)
            button.setTitle(action.state.title, for: 0)
            button.titleLabel().setFont(action.state.style == 1 ? UIFont.boldSystemFont(size: 17) : UIFont.systemFont(size: 17))
            if action.state.style == 2 { button.setTitleColor(UIColor.systemRed(), for: 0) }
            button.addTarget(self, action: ObjCSelector("_perryChoose:"), for: 1 << 6)
            button.setTag(alert.actions.firstIndex { $0.objcObject == action.objcObject } ?? 0)
            panel.addSubview(button)
        }
        // An alert's two actions sit side by side, divided, cancel first;
        // otherwise they are stacked, cancel last.
        var actions = alert.actions
        if let cancel = actions.firstIndex(where: { $0.state.style == 1 }) {
            let action = actions.remove(at: cancel)
            if actions.count == 1 && alert.style == 1 { actions.insert(action, at: 0) } else { actions.append(action) }
        }
        if actions.count == 2 && alert.style == 1 {
            separator(CGRect(x: 0, y: y, width: width, height: Screen.pixel))
            separator(CGRect(x: width / 2, y: y, width: Screen.pixel, height: 44))
            addButton(actions[0], CGRect(x: 0, y: y, width: width / 2, height: 44))
            addButton(actions[1], CGRect(x: width / 2, y: y, width: width / 2, height: 44))
            y += 44
        } else {
            for action in actions {
                separator(CGRect(x: 0, y: y, width: width, height: Screen.pixel))
                addButton(action, CGRect(x: 0, y: y, width: width, height: 44))
                y += 44
            }
        }
        panel.sendSetFrame(CGRect(x: (Screen.bounds.width - width) / 2, y: (Screen.bounds.height - y) / 2, width: width, height: y))
        view.addSubview(panel)
        setView(view)
    }

    /// An action sheet: its title and message, small and gray, above its
    /// actions, in a panel across the bottom of the screen; Cancel in a
    /// panel of its own below. A tap outside the panels cancels.
    private func loadSheet(in view: UIView) {
        let safe = Screen.safeAreaInsets
        let width = min(Screen.bounds.width - safe.left - safe.right - 16, 400)
        let x = (Screen.bounds.width - width) / 2
        func makePanel() -> UIView {
            let panel = UIView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIView.self)
            panel.setBackgroundColor(UIColor.gray(0.97))
            panel.state.geometry.cornerRadius = 14
            panel.state.geometry.masksToBounds = true
            return panel
        }
        func separator(_ panel: UIView, _ y: CGFloat) {
            let line = UIView.objCClass.object.allocated().initializeView(frame: CGRect(x: 0, y: y, width: width, height: Screen.pixel))
                .unsafeCast(to: UIView.self)
            line.setBackgroundColor(UIColor.separator())
            panel.addSubview(line)
        }
        func addButton(_ panel: UIView, _ action: UIAlertAction, _ y: CGFloat) {
            let button = UIButton.button(UIButton.objCClass, type: 1).unsafeCast(to: UIButton.self)
            button.sendSetFrame(CGRect(x: 0, y: y, width: width, height: 57))
            let font = action.state.style == 1 ? UIFont.boldSystemFont(size: 20) : UIFont.systemFont(size: 20)
            // A long title ends in an ellipsis, within the sheet's margins.
            button.setTitle(action.state.title.map { Text.truncated($0, font: font, width: width - 32) }, for: 0)
            button.titleLabel().setFont(font)
            if action.state.style == 2 { button.setTitleColor(UIColor.systemRed(), for: 0) }
            if !action.state.enabled {
                button.setTitleColor(UIColor.systemGray(), for: 0)
                button.setEnabled(false)
            }
            button.addTarget(self, action: ObjCSelector("_perryChoose:"), for: 1 << 6)
            button.setTag(alert.actions.firstIndex { $0.objcObject == action.objcObject } ?? 0)
            panel.addSubview(button)
        }
        var actions = alert.actions
        let cancel = actions.firstIndex { $0.state.style == 1 }.map { actions.remove(at: $0) }
        let panel = makePanel()
        // The title and actions scroll when they are taller than the screen.
        let content = UIScrollView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIScrollView.self)
        content.setShowsVerticalScrollIndicator(true)
        panel.addSubview(content)
        var y: CGFloat = 0
        let header = [(state.title, true), (alert.message, false)].compactMap { text, bold in
            text.flatMap { $0.isEmpty ? nil : ($0, bold) }
        }
        if !header.isEmpty {
            y = 14
            for (text, bold) in header {
                let font = bold ? UIFont.boldSystemFont(size: 13) : UIFont.systemFont(size: 13)
                for line in TextLayout.lines(text, font: font, width: width - 32) {
                    let label = UILabel.objCClass.object.allocated()
                        .initializeView(frame: CGRect(x: 16, y: y, width: width - 32, height: font.lineHeight())).unsafeCast(to: UILabel.self)
                    label.setText(line)
                    label.setFont(font)
                    label.setTextColor(UIColor.systemGray())
                    label.setTextAlignment(1)
                    content.addSubview(label)
                    y += font.lineHeight()
                }
                y += 4
            }
            y += 10
        }
        for (index, action) in actions.enumerated() {
            if index > 0 || !header.isEmpty { separator(content, y) }
            addButton(content, action, y)
            y += 57
        }
        var bottom = Screen.bounds.height - max(safe.bottom, 8)
        if let cancel {
            let outside = UIButton.button(UIButton.objCClass, type: 0).unsafeCast(to: UIButton.self)
            outside.sendSetFrame(Screen.bounds)
            outside.addTarget(self, action: ObjCSelector("_perryChoose:"), for: 1 << 6)
            outside.setTag(alert.actions.firstIndex { $0.objcObject == cancel.objcObject } ?? 0)
            view.addSubview(outside)
            let cancelPanel = makePanel()
            cancelPanel.setBackgroundColor(UIColor.white())
            addButton(cancelPanel, cancel, 0)
            cancelPanel.sendSetFrame(CGRect(x: x, y: bottom - 57, width: width, height: 57))
            view.addSubview(cancelPanel)
            bottom -= 57 + 8
        }
        if y > 0 {
            let top = max(bottom - y, safe.top + 8)
            panel.sendSetFrame(CGRect(x: x, y: top, width: width, height: bottom - top))
            content.sendSetFrame(CGRect(x: 0, y: 0, width: width, height: bottom - top))
            content.setContentSize(CGSize(width: width, height: y))
            view.addSubview(panel)
        }
    }

    @ObjCMethod("_perryChoose:")
    func choose(_ sender: UIButton) {
        let index = sender.state.tag
        guard alert.actions.indices.contains(index) else { return }
        let action = alert.actions[index]
        dismiss(animated: true, completion: nil)
        action.state.handler.map { Blocks.call($0, action) }
    }
}

extension Blocks {
    /// A block taking one object.
    static func call(_ block: ObjCBlock, _ object: NSObject?) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        block.function(as: Invoke.self)(block.object, object?.objcObject)
    }
}

/// The machine's batteries, as Linux lists them in /sys/class/power_supply.
enum PowerSupply {
    static let directory = "/sys/class/power_supply"

    /// The system's battery: a battery whose scope isn't a device's (a
    /// stylus's or a keyboard's), with a charge to report.
    static var battery: String? {
        guard let listing = opendir(directory) else { return nil }
        defer { closedir(listing) }
        var names: [String] = []
        while let entry = readdir(listing) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            if !name.hasPrefix(".") { names.append(name) }
        }
        return names.sorted().first { name in
            read(name, "type") == "Battery" && read(name, "scope") != "Device" && read(name, "capacity") != nil
        }
    }

    /// A supply's attribute, without surrounding white space; nil when it
    /// has none.
    static func read(_ supply: String, _ attribute: String) -> String? {
        guard let file = fopen("\(directory)/\(supply)/\(attribute)", "r") else { return nil }
        defer { fclose(file) }
        var buffer = [CChar](repeating: 0, count: 256)
        guard fgets(&buffer, Int32(buffer.count), file) != nil else { return nil }
        var value = Substring(String(cString: buffer))
        while value.first?.isWhitespace == true { value.removeFirst() }
        while value.last?.isWhitespace == true { value.removeLast() }
        return value.isEmpty ? nil : String(value)
    }
}
