import CPerryGeometry
import PerryObjCInterop

// UITextField: one line of text, or its placeholder, drawn inside its
// border style. It takes no keyboard input yet; what an app sets, it shows
// and reads back.

final class TextFieldState: ObjectState {
    var text: String?
    var attributedText: NSObject?
    var placeholder: String?
    var attributedPlaceholder: NSObject?
    var font: UIFont?
    var textColor: UIColor?
    /// NSTextAlignment: natural 4.
    var textAlignment = 4
    /// UITextBorderStyle: none 0, line 1, bezel 2, rounded rect 3.
    var borderStyle = 0
    var clearButtonMode = 0
    var delegate: UnsafeMutableRawPointer?
    var leftView: UIView?
    var rightView: UIView?
    var leftViewMode = 0
    var rightViewMode = 0
    var inputView: UIView?
    var inputAccessoryView: UIView?
    var secure = false
    var keyboardType = 0
    var returnKeyType = 0
    var autocapitalizationType = 2
    var autocorrectionType = 0
    var spellCheckingType = 0
    var clearsOnBeginEditing = false
    var adjustsFontSizeToFitWidth = false
    var minimumFontSize: CGFloat = 0
    var editing = false
}

@ObjCClass("UITextField")
open class UITextField: UIControl {
    static let fieldStates = StateTable<TextFieldState>()
    var field: TextFieldState { UITextField.fieldStates[objcObject] }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let field = field
        field.text = decoded.string("UIText")
        field.placeholder = decoded.string("UIPlaceholder")
        field.font = decoded.object("UIFont")?.as(UIFont.self)
        field.textColor = decoded.object("UITextColor")?.as(UIColor.self)
        if decoded.has("UITextAlignment") { field.textAlignment = decoded.integer("UITextAlignment") }
        field.borderStyle = decoded.integer("UIBorderStyle")
        field.clearButtonMode = decoded.integer("UIClearButtonMode")
        field.secure = decoded.bool("UISecureTextEntry")
        field.keyboardType = decoded.integer("UIKeyboardType")
        field.returnKeyType = decoded.integer("UIReturnKeyType")
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITextField.fieldStates.remove(objcObject)
        super.dealloc()
    }

    var font: UIFont { field.font ?? UIFont.systemFont(size: 17) }

    @ObjCMethod("text") func text() -> String? { field.text ?? "" }
    @ObjCMethod("setText:") func setText(_ text: String?) { field.text = text; field.attributedText = nil; setNeedsDisplay() }
    @ObjCMethod("attributedText") func attributedText() -> NSObject? { field.attributedText }
    @ObjCMethod("setAttributedText:") func setAttributedText(_ text: NSObject?) {
        field.attributedText = text
        field.text = text?.sendString()
        setNeedsDisplay()
    }
    @ObjCMethod("placeholder") func placeholder() -> String? { field.placeholder }
    @ObjCMethod("setPlaceholder:") func setPlaceholder(_ placeholder: String?) { field.placeholder = placeholder; setNeedsDisplay() }
    @ObjCMethod("attributedPlaceholder") func attributedPlaceholder() -> NSObject? { field.attributedPlaceholder }
    @ObjCMethod("setAttributedPlaceholder:") func setAttributedPlaceholder(_ placeholder: NSObject?) {
        field.attributedPlaceholder = placeholder
        field.placeholder = placeholder?.sendString()
        setNeedsDisplay()
    }
    @ObjCMethod("font") func fontObject() -> UIFont { font }
    @ObjCMethod("setFont:") func setFont(_ font: UIFont?) { field.font = font; setNeedsDisplay(); superviewNeedsLayout() }
    @ObjCMethod("textColor") func textColor() -> UIColor { field.textColor ?? UIColor.label() }
    @ObjCMethod("setTextColor:") func setTextColor(_ color: UIColor?) { field.textColor = color; setNeedsDisplay() }
    @ObjCMethod("textAlignment") func textAlignment() -> Int { field.textAlignment }
    @ObjCMethod("setTextAlignment:") func setTextAlignment(_ alignment: Int) { field.textAlignment = alignment; setNeedsDisplay() }
    @ObjCMethod("borderStyle") func borderStyle() -> Int { field.borderStyle }
    @ObjCMethod("setBorderStyle:") func setBorderStyle(_ style: Int) { field.borderStyle = style; setNeedsDisplay() }
    @ObjCMethod("clearButtonMode") func clearButtonMode() -> Int { field.clearButtonMode }
    @ObjCMethod("setClearButtonMode:") func setClearButtonMode(_ mode: Int) { field.clearButtonMode = mode }
    @ObjCMethod("delegate") func delegate() -> NSObject? { field.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { field.delegate = delegate?.objcObject }
    @ObjCMethod("leftView") func leftView() -> UIView? { field.leftView }
    @ObjCMethod("setLeftView:") func setLeftView(_ view: UIView?) {
        field.leftView?.removeFromSuperview()
        field.leftView = view
        if let view { addSubview(view) }
        setNeedsLayout()
    }
    @ObjCMethod("rightView") func rightView() -> UIView? { field.rightView }
    @ObjCMethod("setRightView:") func setRightView(_ view: UIView?) {
        field.rightView?.removeFromSuperview()
        field.rightView = view
        if let view { addSubview(view) }
        setNeedsLayout()
    }
    @ObjCMethod("leftViewMode") func leftViewMode() -> Int { field.leftViewMode }
    @ObjCMethod("setLeftViewMode:") func setLeftViewMode(_ mode: Int) { field.leftViewMode = mode }
    @ObjCMethod("rightViewMode") func rightViewMode() -> Int { field.rightViewMode }
    @ObjCMethod("setRightViewMode:") func setRightViewMode(_ mode: Int) { field.rightViewMode = mode }
    @ObjCMethod("inputView") func inputView() -> UIView? { field.inputView }
    @ObjCMethod("setInputView:") func setInputView(_ view: UIView?) { field.inputView = view }
    @ObjCMethod("inputAccessoryView") func inputAccessoryView() -> UIView? { field.inputAccessoryView }
    @ObjCMethod("setInputAccessoryView:") func setInputAccessoryView(_ view: UIView?) { field.inputAccessoryView = view }
    @ObjCMethod("isSecureTextEntry") func isSecureTextEntry() -> Bool { field.secure }
    @ObjCMethod("setSecureTextEntry:") func setSecureTextEntry(_ secure: Bool) { field.secure = secure; setNeedsDisplay() }
    @ObjCMethod("keyboardType") func keyboardType() -> Int { field.keyboardType }
    @ObjCMethod("setKeyboardType:") func setKeyboardType(_ type: Int) { field.keyboardType = type }
    @ObjCMethod("returnKeyType") func returnKeyType() -> Int { field.returnKeyType }
    @ObjCMethod("setReturnKeyType:") func setReturnKeyType(_ type: Int) { field.returnKeyType = type }
    @ObjCMethod("autocapitalizationType") func autocapitalizationType() -> Int { field.autocapitalizationType }
    @ObjCMethod("setAutocapitalizationType:") func setAutocapitalizationType(_ type: Int) { field.autocapitalizationType = type }
    @ObjCMethod("autocorrectionType") func autocorrectionType() -> Int { field.autocorrectionType }
    @ObjCMethod("setAutocorrectionType:") func setAutocorrectionType(_ type: Int) { field.autocorrectionType = type }
    @ObjCMethod("spellCheckingType") func spellCheckingType() -> Int { field.spellCheckingType }
    @ObjCMethod("setSpellCheckingType:") func setSpellCheckingType(_ type: Int) { field.spellCheckingType = type }
    @ObjCMethod("clearsOnBeginEditing") func clearsOnBeginEditing() -> Bool { field.clearsOnBeginEditing }
    @ObjCMethod("setClearsOnBeginEditing:") func setClearsOnBeginEditing(_ clears: Bool) { field.clearsOnBeginEditing = clears }
    @ObjCMethod("adjustsFontSizeToFitWidth") func adjustsFontSizeToFitWidth() -> Bool { field.adjustsFontSizeToFitWidth }
    @ObjCMethod("setAdjustsFontSizeToFitWidth:") func setAdjustsFontSizeToFitWidth(_ adjusts: Bool) { field.adjustsFontSizeToFitWidth = adjusts }
    @ObjCMethod("minimumFontSize") func minimumFontSize() -> CGFloat { field.minimumFontSize }
    @ObjCMethod("setMinimumFontSize:") func setMinimumFontSize(_ size: CGFloat) { field.minimumFontSize = size }
    @ObjCMethod("isEditing") func isEditing() -> Bool { field.editing }

    /// Without a keyboard, a field does not become first responder.
    @ObjCMethod("canBecomeFirstResponder") override func canBecomeFirstResponder() -> Bool { false }
    @ObjCMethod("becomeFirstResponder") override func becomeFirstResponder() -> Bool { false }
    @ObjCMethod("resignFirstResponder") override func resignFirstResponder() -> Bool { true }

    /// One line, with the border's insets.
    @ObjCMethod("intrinsicContentSize")
    func intrinsicContentSize() -> CGSize {
        let text = field.text.flatMap { $0.isEmpty ? nil : $0 } ?? field.placeholder ?? ""
        let size = Text.size(text, font: font)
        let inset: CGFloat = field.borderStyle == 0 ? 0 : 7
        return CGSize(width: size.width + inset * 2, height: max(size.height + 4, field.borderStyle == 3 ? 34 : size.height))
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize() }

    /// The text's area: inside the border, between the side views.
    @ObjCMethod("textRectForBounds:")
    func textRect(forBounds bounds: CGRect) -> CGRect {
        let inset: CGFloat = field.borderStyle == 0 ? 0 : 7
        var rect = CGRect(x: bounds.minX + inset, y: bounds.minY, width: max(bounds.width - inset * 2, 0), height: bounds.height)
        if let left = field.leftView { rect.origin.x += left.state.bounds.width; rect.size.width -= left.state.bounds.width }
        if let right = field.rightView { rect.size.width -= right.state.bounds.width }
        return rect
    }

    @ObjCMethod("editingRectForBounds:") func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    @ObjCMethod("placeholderRectForBounds:") func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = state.bounds
        if let left = field.leftView {
            let size = left.state.bounds.size
            left.sendSetFrame(CGRect(x: field.borderStyle == 0 ? 0 : 7, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
        if let right = field.rightView {
            let size = right.state.bounds.size
            right.sendSetFrame(CGRect(x: bounds.width - size.width - (field.borderStyle == 0 ? 0 : 7), y: (bounds.height - size.height) / 2,
                                      width: size.width, height: size.height))
        }
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        if field.borderStyle == 3 {
            let fill = UIColor.systemGray6()
            withExtendedLifetime(fill) {
                let path = CG.pathCreateMutable()
                defer { CG.release(path) }
                CG.pathAddRoundedRect(path, nil, bounds, 5, 5)
                CG.setFillColorWithColor(context, fill.state.makeCGColor())
                CG.addPath(context, path)
                CG.fillPath(context)
            }
        } else if field.borderStyle == 1 || field.borderStyle == 2 {
            let line = UIColor.separator()
            withExtendedLifetime(line) {
                CG.setStrokeColorWithColor(context, line.state.makeCGColor())
                CG.setLineWidth(context, Screen.pixel)
                let half = Screen.pixel / 2
                CG.strokeRect(context, CGRect(x: half, y: half, width: bounds.width - Screen.pixel, height: bounds.height - Screen.pixel))
            }
        }
        let area = textRect(forBounds: bounds)
        var shown = field.text ?? ""
        var color = textColor()
        if shown.isEmpty {
            shown = field.placeholder ?? ""
            color = UIColor.placeholderText()
        } else if field.secure {
            shown = String(repeating: "•", count: shown.count)
        }
        guard !shown.isEmpty else { return }
        let line = Text.truncated(shown, font: font, width: area.width)
        let width = Text.width(line, font: font).rounded(.up)
        let x: CGFloat
        switch field.textAlignment {
        case 1: x = area.midX - width / 2
        case 2: x = area.maxX - width
        default: x = area.minX
        }
        Text.draw(line, at: CGPoint(x: x, y: area.midY - Text.lineHeight(font) / 2), font: font, color: color)
    }
}
