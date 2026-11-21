import PerryObjCInterop

// NSRunAlertPanel and its informational and critical forms: an alert of a
// title, a message made from a format and its arguments, and up to three
// buttons. They are variadic, so each comes here from CPerryAppKit's
// variadic.S with a Darwin va_list of the format's arguments.

private typealias Object = UnsafeMutableRawPointer

/// Runs the alert and answers NSAlertDefaultReturn (1), NSAlertAlternateReturn
/// (0) or NSAlertOtherReturn (-1) for the button chosen. With no default
/// title the button is "OK".
private func runAlertPanel(style: UInt, _ title: Object?, _ format: Object?, _ defaultButton: Object?, _ alternateButton: Object?,
                           _ otherButton: Object?, _ arguments: UnsafeRawPointer?) -> Int {
    func string(_ object: Object?) -> String? { object.map { String(objCArgument: $0) } }
    var message = ""
    if let format, let cls = Classes.named("NSString"), let allocated = Send.object(cls.pointer, "alloc") {
        typealias Make = @convention(c) (Object, UnsafeRawPointer, Object?, UnsafeRawPointer?) -> Object?
        if let made = unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(allocated, ObjCRuntime.selector("initWithFormat:arguments:"), format, arguments) {
            message = String(objCArgument: made)
            ObjCRuntime.release(made)
        }
    }
    let alert = NSAlert()
    alert.messageText = string(title) ?? "Alert"
    alert.informativeText = message
    alert.style = style
    _ = alert.addButton(title: string(defaultButton) ?? "OK")
    // A missing alternate with an other button still answers as the other.
    var answers = [1]
    if let alternate = string(alternateButton) {
        _ = alert.addButton(title: alternate)
        answers.append(0)
    }
    if let other = string(otherButton) {
        _ = alert.addButton(title: other)
        answers.append(-1)
    }
    let chosen = alert.runModal() - 1000
    return answers.indices.contains(chosen) ? answers[chosen] : 1
}

@c
public func perry_appkit_run_alert_panel(_ title: UnsafeMutableRawPointer?, _ format: UnsafeMutableRawPointer?,
                                         _ defaultButton: UnsafeMutableRawPointer?, _ alternateButton: UnsafeMutableRawPointer?,
                                         _ otherButton: UnsafeMutableRawPointer?, _ arguments: UnsafeRawPointer?) -> Int {
    runAlertPanel(style: 0, title, format, defaultButton, alternateButton, otherButton, arguments)
}

@c
public func perry_appkit_run_informational_alert_panel(_ title: UnsafeMutableRawPointer?, _ format: UnsafeMutableRawPointer?,
                                                       _ defaultButton: UnsafeMutableRawPointer?, _ alternateButton: UnsafeMutableRawPointer?,
                                                       _ otherButton: UnsafeMutableRawPointer?, _ arguments: UnsafeRawPointer?) -> Int {
    runAlertPanel(style: 1, title, format, defaultButton, alternateButton, otherButton, arguments)
}

@c
public func perry_appkit_run_critical_alert_panel(_ title: UnsafeMutableRawPointer?, _ format: UnsafeMutableRawPointer?,
                                                  _ defaultButton: UnsafeMutableRawPointer?, _ alternateButton: UnsafeMutableRawPointer?,
                                                  _ otherButton: UnsafeMutableRawPointer?, _ arguments: UnsafeRawPointer?) -> Int {
    runAlertPanel(style: 2, title, format, defaultButton, alternateButton, otherButton, arguments)
}
