import PerryObjCInterop

// Classes Perry has no implementation of, registered as plain subclasses of
// the nearest class it has, so a program that looks them up by name finds
// them: AppKit controls and controllers not written yet, one of AppKit's
// private cells, and the views and controllers of frameworks there is no
// provider for (AddressBook, Automator, DiscRecording, ImageKit, OSAKit,
// PDFKit, Quartz Composer, QTKit). Xcode 4's Interface Builder looks up
// every class it integrates when it starts, and stops at a missing one.
// A stand-in does what its superclass does: a slider is a control with a
// value, a PDF view an empty view.

enum StandInClasses {
    /// Each class, after its superclass where that is a stand-in too.
    static let classes: [(name: String, superclass: String)] = [
        // AppKit.
        ("NSSlider", "NSControl"), ("NSSliderCell", "NSActionCell"), ("NSColorScaleSliderCell", "NSSliderCell"),
        ("NSStepper", "NSControl"), ("NSStepperCell", "NSActionCell"),
        ("NSLevelIndicator", "NSControl"), ("NSLevelIndicatorCell", "NSActionCell"),
        ("NSTokenField", "NSTextField"), ("NSTokenFieldCell", "NSTextFieldCell"),
        ("NSDrawer", "NSResponder"), ("NSForm", "NSMatrix"), ("NSCollectionViewItem", "NSViewController"),
        ("NSRuleEditor", "NSControl"), ("NSPredicateEditor", "NSRuleEditor"), ("NSPredicateEditorRowTemplate", "NSObject"),
        ("NSMenuItemCell", "NSButtonCell"), ("NSToolbarSeparatorItem", "NSToolbarItem"),
        ("NSDictionaryController", "NSArrayController"), ("NSPageController", "NSViewController"), ("NSTextFinder", "NSObject"),
        // AddressBook.
        ("ABPeoplePickerView", "NSView"), ("ABPersonView", "NSView"),
        // Automator.
        ("AMGroupBox", "NSBox"), ("AMPopUpButton", "NSPopUpButton"), ("AMPathPopUpButton", "NSPopUpButton"),
        ("_AMVariablePopUpButton", "NSPopUpButton"), ("_AMVariablePopUpButtonCell", "NSPopUpButtonCell"),
        ("AMTokenField", "NSTokenField"), ("AMTokenFieldCell", "NSTokenFieldCell"),
        ("AMWorkflowController", "NSController"), ("AMWorkflowView", "NSView"),
        // DiscRecording.
        ("DRMSFFormatter", "NSFormatter"),
        // ImageKit.
        ("IKCameraDeviceView", "NSView"), ("IKDeviceBrowserView", "NSView"), ("IKImageBrowserView", "NSView"),
        ("IKImageView", "NSView"), ("IKScannerDeviceView", "NSView"),
        // OSAKit.
        ("OSAScriptController", "NSController"), ("OSAScriptView", "NSTextView"), ("OSASplitView", "NSSplitView"),
        ("OSADictionaryController", "NSObject"), ("OSADictionaryView", "NSView"), ("OSAImageTextCell", "NSTextFieldCell"),
        // PDFKit.
        ("PDFView", "NSView"), ("PDFThumbnailView", "NSView"),
        // Quartz Composer.
        ("QCView", "NSView"), ("QCPatchController", "NSObjectController"), ("QCCompositionParameterView", "NSView"),
        ("QCCompositionPickerView", "NSView"), ("QCPatchParametersView", "NSView"), ("QCPatchEditorView", "NSView"),
        ("QCPatchBrowserView", "NSView"), ("GFGraphEditorView", "NSView"), ("GFGraphBrowserView", "NSView"),
        // QTKit.
        ("QTMovieView", "NSView"), ("QTCaptureView", "NSView"),
        // A nib's stand-in for a class Interface Builder swapped in by name,
        // which Perry's nib loader reads itself.
        ("NSClassSwapper", "NSObject"),
    ]

    /// Methods stand-ins answer, that a program looks up on them (Interface
    /// Builder swizzles them): -initWithCoder: answers the object, the
    /// others nothing.
    static let methods: [(cls: String, selector: String, types: String)] = [
        ("NSClassSwapper", "initWithCoder:", "@24@0:8@16"),
        ("NSPredicateEditor", "_forceUseDelegate", "c16@0:8"),
    ]

    private static let returnsSelf: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { object, _, _ in object }
    private static let returnsZero: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int = { _, _ in 0 }

    nonisolated(unsafe) private static var registered = false

    /// A stand-in's class or metaclass, for an image that imports it from
    /// AppKit (Interface Builder swizzles NSClassSwapper's -initWithCoder:
    /// through its class reference).
    static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        let metaclassPrefix = "_OBJC_METACLASS_$_", classPrefix = "_OBJC_CLASS_$_"
        let isMeta = name.hasPrefix(metaclassPrefix)
        guard isMeta || name.hasPrefix(classPrefix) else { return nil }
        let className = String(name.dropFirst(isMeta ? metaclassPrefix.count : classPrefix.count))
        // Images bound before AppKit's provider starts keep the loader's
        // placeholder, as they did.
        guard ObjCRuntime.isInstalled, classes.contains(where: { $0.name == className }) else { return nil }
        register()
        guard let cls = ObjCRuntime.functions.getClass(className) else { return nil }
        return isMeta ? ObjCRuntime.functions.objectGetClass(cls) : cls
    }

    /// Registers each class no image or provider defines, once.
    static func register() {
        guard !registered else { return }
        registered = true
        let functions = ObjCRuntime.functions
        for (name, superclass) in classes {
            guard functions.getClass(name) == nil, let parent = functions.getClass(superclass),
                  let cls = name.withCString({ functions.allocateClassPair(parent, $0, 0) }) else { continue }
            functions.registerClassPair(cls)
        }
        for (name, selector, types) in methods {
            guard let cls = functions.getClass(name) else { continue }
            let imp = types.hasPrefix("@24") ? unsafeBitCast(returnsSelf, to: UnsafeRawPointer.self) : unsafeBitCast(returnsZero, to: UnsafeRawPointer.self)
            _ = functions.addMethod(cls, functions.registerSelector(selector), imp, types)
        }
    }
}
