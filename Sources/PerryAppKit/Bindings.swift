import PerryObjCInterop

// Cocoa bindings, NSObject's NSKeyValueBindingCreation: a binding observes
// the bound object's key path and sets the receiver's binding from it, now
// and whenever it changes. The binding name is the receiver's key ("value"
// is a control's object value), unless it is one of the names below.
// Changes made in the receiver go back only through -setValue:forKey: on
// the binding name, which the app calls itself.

private typealias Object = UnsafeMutableRawPointer

private func send(_ receiver: Object?, _ selector: String, _ observer: Object?, _ keyPath: Object?, _ options: UInt, _ context: Object?) {
    typealias Fn = @convention(c) (Object?, UnsafeRawPointer, Object?, Object?, UInt, Object?) -> Void
    unsafeBitCast(ObjCRuntime.msgSend, to: Fn.self)(receiver, ObjCRuntime.selector(selector), observer, keyPath, options, context)
}

private func send(_ receiver: Object?, _ selector: String, int value: Int) {
    typealias Fn = @convention(c) (Object?, UnsafeRawPointer, Int) -> Void
    unsafeBitCast(ObjCRuntime.msgSend, to: Fn.self)(receiver, ObjCRuntime.selector(selector), value)
}

private func integer(_ receiver: Object?) -> Int {
    typealias Fn = @convention(c) (Object?, UnsafeRawPointer) -> Int
    return unsafeBitCast(ObjCRuntime.msgSend, to: Fn.self)(receiver, ObjCRuntime.selector("integerValue"))
}

@ObjCClass("_PerryBinding")
final class _PerryBinding: NSObject {
    /// Not retained: the receiver owns its bindings.
    var receiver: UnsafeMutableRawPointer?
    var name = ""
    var observed: NSObject?
    var keyPath = ""
    var options: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    func start() {
        guard let observed else { return }
        // NSKeyValueObservingOptionInitial | New.
        let path = NSObject(objCReturnValue: keyPath.objCReturnValue())
        send(observed.objcObject, "addObserver:forKeyPath:options:context:", objcObject, path.objcObject, 5, nil)
    }

    func stop() {
        guard let observed else { return }
        let path = NSObject(objCReturnValue: keyPath.objCReturnValue())
        Send.void(observed.objcObject, "removeObserver:forKeyPath:", objcObject, path.objcObject)
        self.observed = nil
    }

    @ObjCMethod("observeValueForKeyPath:ofObject:change:context:")
    func observeValue(forKeyPath path: String?, of object: NSObject?, change: NSObject?, context: UnsafeMutableRawPointer?) {
        update()
    }

    /// The bound value, transformed as the options say, set in the receiver.
    func update() {
        guard let receiver, let observed else { return }
        var value = observed.sendValue(forKeyPath: keyPath)
        let options = self.options?.as(NSDictionary.self)
        if let name = options?.object(forKey: "NSValueTransformerName"),
           let transformerClass = Classes.named("NSValueTransformer"),
           let transformer = Send.object(transformerClass.pointer, "valueTransformerForName:", name.objcObject) {
            value = Send.object(transformer, "transformedValue:", value?.objcObject).map(NSObject.init)
        } else if let transformer = options?.object(forKey: "NSValueTransformer") {
            value = Send.object(transformer.objcObject, "transformedValue:", value?.objcObject).map(NSObject.init)
        }
        if value == nil, let placeholder = options?.object(forKey: "NSNullPlaceholder") { value = placeholder }
        let target = NSObject(receiver)
        switch name {
        case "value":
            if target.responds(to: "setObjectValue:") {
                Send.void(receiver, "setObjectValue:", value?.objcObject)
            } else {
                assign(target, value)
            }
        case "hidden", "enabled", "editable", "selectable":
            let on = value.map { Send.bool($0.objcObject, "boolValue") } ?? false
            let setter = "set" + name.prefix(1).uppercased() + name.dropFirst() + ":"
            if target.responds(to: setter) { Send.void(receiver, setter, bool: on) }
        case "title", "toolTip", "font", "textColor", "image", "contentArray", "content", "contentObject",
             "selectionIndexes", "sortDescriptors", "selectedIndex", "selectedTag", "selectedObject", "selectedValue":
            let setter = "set" + name.prefix(1).uppercased() + name.dropFirst() + ":"
            // A pop-up button or segmented control selects by index or tag.
            let selector = name == "selectedIndex" ? "selectItemAtIndex:" : "selectItemWithTag:"
            if name == "selectedIndex" || name == "selectedTag", target.responds(to: selector) {
                send(receiver, selector, int: value.map { integer($0.objcObject) } ?? -1)
            } else if target.responds(to: setter) {
                Send.void(receiver, setter, value?.objcObject)
            } else {
                assign(target, value)
            }
        default:
            assign(target, value)
        }
    }

    /// Sets the bound value through the receiver's setter for the binding's
    /// name; a receiver with none (a menu item's "value", say) keeps what it
    /// has, as AppKit's binders do for names they don't apply.
    private func assign(_ target: NSObject, _ value: NSObject?) {
        let setter = "set" + name.prefix(1).uppercased() + name.dropFirst() + ":"
        if target.responds(to: setter) {
            Send.void(target.objcObject, setter, value?.objcObject)
        } else {
            appKitWarning("binding \(name) of \(target.objCClass.pointer) has no setter; skipped")
        }
    }

    func info() -> NSObject {
        let dictionary = NSMutableDictionary.empty()
        if let observed { dictionary.set(observed, forKey: "NSObservedObject") }
        dictionary.set(NSObject(objCReturnValue: keyPath.objCReturnValue()), forKey: "NSObservedKeyPath")
        if let options { dictionary.set(options, forKey: "NSOptions") }
        return dictionary
    }
}

enum BindingTable {
    /// Each receiver's bindings by name.
    nonisolated(unsafe) static var bindings: [UnsafeMutableRawPointer: [String: _PerryBinding]] = [:]

    static func bind(_ receiver: UnsafeMutableRawPointer, _ name: String, to observed: NSObject, keyPath: String, options: NSObject?) {
        unbind(receiver, name)
        let binding = _PerryBinding()
        binding.receiver = receiver
        binding.name = name
        binding.observed = observed
        binding.keyPath = keyPath
        binding.options = options
        bindings[receiver, default: [:]][name] = binding
        binding.start()
    }

    static func unbind(_ receiver: UnsafeMutableRawPointer, _ name: String) {
        bindings[receiver]?.removeValue(forKey: name)?.stop()
        if bindings[receiver]?.isEmpty == true { bindings[receiver] = nil }
    }
}

/// Binding names, their options and the keys of -infoForBinding:.
@ObjCConstants
enum BindingNames {
    static let NSValueBinding = "value"
    static let NSHiddenBinding = "hidden"
    static let NSEnabledBinding = "enabled"
    static let NSEditableBinding = "editable"
    static let NSContentBinding = "content"
    static let NSContentArrayBinding = "contentArray"
    static let NSContentObjectBinding = "contentObject"
    static let NSContentValuesBinding = "contentValues"
    static let NSSelectionIndexesBinding = "selectionIndexes"
    static let NSSelectionIndexPathsBinding = "selectionIndexPaths"
    static let NSTitleBinding = "title"
    static let NSToolTipBinding = "toolTip"
    static let NSFontBinding = "font"
    static let NSTextColorBinding = "textColor"
    static let NSImageBinding = "image"
    static let NSSelectedIndexBinding = "selectedIndex"
    static let NSSelectedObjectBinding = "selectedObject"
    static let NSSelectedValueBinding = "selectedValue"
    static let NSSelectedTagBinding = "selectedTag"
    static let NSSortDescriptorsBinding = "sortDescriptors"
    static let NSSelectableBinding = "selectable"
    static let NSAlignmentBinding = "alignment"
    static let NSDataBinding = "data"
    static let NSDoubleClickArgumentBinding = "doubleClickArgument"
    static let NSDoubleClickTargetBinding = "doubleClickTarget"
    static let NSArgumentBinding = "argument"
    static let NSTargetBinding = "target"
    static let NSMaxValueBinding = "maxValue"
    static let NSMinValueBinding = "minValue"
    static let NSPredicateBinding = "predicate"
    static let NSContentSetBinding = "contentSet"
    static let NSManagedObjectContextBinding = "managedObjectContext"
    static let NSAnimateBinding = "animate"
    static let NSDisplayPatternBinding = "displayPattern"
    static let NSLabelBinding = "label"
    static let NSVisibleBinding = "visible"
    static let NSValueTransformerNameBindingOption = "NSValueTransformerName"
    static let NSValueTransformerBindingOption = "NSValueTransformer"
    static let NSNullPlaceholderBindingOption = "NSNullPlaceholder"
    static let NSNoSelectionPlaceholderBindingOption = "NSNoSelectionPlaceholder"
    static let NSMultipleValuesPlaceholderBindingOption = "NSMultipleValuesPlaceholder"
    static let NSNotApplicablePlaceholderBindingOption = "NSNotApplicablePlaceholder"
    static let NSContinuouslyUpdatesValueBindingOption = "NSContinuouslyUpdatesValue"
    static let NSRaisesForNotApplicableKeysBindingOption = "NSRaisesForNotApplicableKeys"
    static let NSAllowsEditingMultipleValuesSelectionBindingOption = "NSAllowsEditingMultipleValuesSelection"
    static let NSAllowsNullArgumentBindingOption = "NSAllowsNullArgument"
    static let NSAlwaysPresentsApplicationModalAlertsBindingOption = "NSAlwaysPresentsApplicationModalAlerts"
    static let NSConditionallySetsEditableBindingOption = "NSConditionallySetsEditable"
    static let NSConditionallySetsEnabledBindingOption = "NSConditionallySetsEnabled"
    static let NSConditionallySetsHiddenBindingOption = "NSConditionallySetsHidden"
    static let NSCreatesSortDescriptorBindingOption = "NSCreatesSortDescriptor"
    static let NSDeletesObjectsOnRemoveBindingOption = "NSDeletesObjectsOnRemove"
    static let NSDisplayNameBindingOption = "NSDisplayName"
    static let NSDisplayPatternBindingOption = "NSDisplayPattern"
    static let NSHandlesContentAsCompoundValueBindingOption = "NSHandlesContentAsCompoundValue"
    static let NSInsertsNullPlaceholderBindingOption = "NSInsertsNullPlaceholder"
    static let NSInvokesSeparatelyWithArrayObjectsBindingOption = "NSInvokesSeparatelyWithArrayObjects"
    static let NSValidatesImmediatelyBindingOption = "NSValidatesImmediately"
    static let NSSelectorNameBindingOption = "NSSelectorName"
    static let NSContentPlacementTagBindingOption = "NSContentPlacementTag"
    static let NSPredicateBindingOption = "NSPredicate"
    static let NSObservedObjectKey = "NSObservedObject"
    static let NSObservedKeyPathKey = "NSObservedKeyPath"
    static let NSOptionsKey = "NSOptions"
}

@ObjCCategory("NSKeyValueBindingCreation")
extension NSObject {
    @ObjCMethod("bind:toObject:withKeyPath:options:")
    func bind(_ name: String?, toObject observed: NSObject?, withKeyPath keyPath: String?, options: NSObject?) {
        guard let name, let observed, let keyPath else { return }
        BindingTable.bind(objcObject, name, to: observed, keyPath: keyPath, options: options)
    }

    @ObjCMethod("unbind:")
    func unbind(_ name: String?) {
        guard let name else { return }
        BindingTable.unbind(objcObject, name)
    }

    @ObjCMethod("infoForBinding:")
    func info(forBinding name: String?) -> NSObject? {
        guard let name else { return nil }
        return BindingTable.bindings[objcObject]?[name]?.info()
    }

    @ObjCMethod("exposedBindings")
    func exposedBindings() -> NSObject { NSMutableArray.of(["value", "hidden", "enabled"].map { NSObject(objCReturnValue: $0.objCReturnValue()) }) }

    @ObjCClassMethod("exposeBinding:") static func exposeBinding(_ name: String?) {}
    @ObjCMethod("valueClassForBinding:") func valueClass(forBinding name: String?) -> NSObject? { nil }
    @ObjCMethod("optionDescriptionsForBinding:") func optionDescriptions(forBinding name: String?) -> NSObject? { nil }
}
