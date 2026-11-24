import CPerryFoundation
import PerryObjCInterop

// NSUndoManager: groups of actions that undo what was done, kept on an undo
// stack, and the actions they register in turn on the redo stack.
// Actions are a target and selector with an object, a block, or a message
// sent to the manager after -prepareWithInvocationTarget:, which forwarding
// hands it as an NSInvocation (arm64 and x86_64, where Foundation forwards).

/// One action: a message to send, an invocation to invoke, or a block to
/// call with the target.
final class UndoAction {
    let target: id?
    let selector: ObjCSelector?
    let object: id?
    let block: id?
    let invocation: id?

    init(target: id?, selector: ObjCSelector?, object: id?, block: id?, invocation: id? = nil) {
        self.target = target.flatMap { ObjC.retain($0) }
        self.selector = selector
        self.object = object.flatMap { ObjC.retain($0) }
        self.block = block.flatMap { ObjC.retainBlock($0) }
        self.invocation = invocation.flatMap { ObjC.retain($0) }
    }

    deinit {
        if let target { ObjC.release(target) }
        if let object { ObjC.release(object) }
        if let block { ObjC.release(block) }
        if let invocation { ObjC.release(invocation) }
    }

    func perform() {
        if let block {
            typealias Invoke = @convention(c) (id, id?) -> Void
            Blocks.invoke(block, as: Invoke.self)(block, target)
        } else if let invocation {
            _ = ObjC.send(invocation, ObjC.selector("invoke"))
        } else if let selector {
            _ = ObjC.send(target, selector.pointer.assumingMemoryBound(to: CChar.self), object)
        }
    }
}

final class UndoGroup {
    var actions: [UndoAction] = []
    var name = ""
    /// -setActionIsDiscardable:'s mark.
    var discardable = false
    /// -setActionUserInfoValue:forKey:'s values, retained.
    var userInfo: [String: id] = [:]

    deinit {
        for value in userInfo.values { ObjC.release(value) }
    }
}

@ObjCClass("NSUndoManager")
open class NSUndoManager: NSObject {
    var undoStack: [UndoGroup] = []
    var redoStack: [UndoGroup] = []
    /// Groups begun and not yet ended, innermost last.
    var open: [UndoGroup] = []
    var undoing = false
    var redoing = false
    var disabled = 0
    var groupsByEvent = true
    var levels = 0
    var runLoopModes: id?
    /// -prepareWithInvocationTarget:'s target, for the next message the
    /// manager forwards; not retained, as Darwin doesn't.
    var preparedTarget: id?

    @ObjCMethod("init")
    public required override init() { super.init() }

    private func post(_ name: String, userInfo: id? = nil) {
        guard let center = "NSNotificationCenter".withCString({ ObjC.getClass($0) }),
              let defaultCenter = ObjC.send(UnsafeMutableRawPointer(center), ObjC.selector("defaultCenter")) else { return }
        typealias Post = @convention(c) (id?, SEL, id?, id?, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: Post.self)(defaultCenter, ObjC.selector("postNotificationName:object:userInfo:"),
                                                   Strings.autoreleased(name), objcObject, userInfo)
    }

    // MARK: Groups

    @ObjCMethod("beginUndoGrouping")
    func beginUndoGrouping() {
        open.append(UndoGroup())
        if open.count == 1 { post("NSUndoManagerDidOpenUndoGroupNotification") }
    }

    @ObjCMethod("endUndoGrouping")
    func endUndoGrouping() {
        guard let group = open.popLast() else { return }
        if let outer = open.last {
            // Discardable only if everything in it is.
            outer.discardable = outer.actions.isEmpty ? group.discardable : outer.discardable && group.discardable
            outer.actions.append(contentsOf: group.actions)
            if outer.name.isEmpty { outer.name = group.name }
            for (key, value) in group.userInfo where outer.userInfo[key] == nil { outer.userInfo[key] = ObjC.retain(value) }
            return
        }
        post("NSUndoManagerWillCloseUndoGroupNotification")
        guard !group.actions.isEmpty else { return }
        if undoing {
            redoStack.append(group)
        } else {
            undoStack.append(group)
            if !redoing { redoStack.removeAll() }
            if levels > 0, undoStack.count > levels { undoStack.removeFirst(undoStack.count - levels) }
        }
        // NSUndoManagerGroupIsDiscardableKey, by value (another file
        // exports the constant), for a discardable group.
        let info = group.discardable
            ? Dictionaries.autoreleased([(key: Strings.autoreleased("NSUndoManagerGroupIsDiscardableKey"),
                                          value: perry_foundation_boolean(1)!)])
            : nil
        post("NSUndoManagerDidCloseUndoGroupNotification", userInfo: info)
    }

    @ObjCMethod("groupingLevel") func groupingLevel() -> Int { open.count }
    @ObjCMethod("groupsByEvent") func groupsByEventValue() -> Bool { groupsByEvent }
    @ObjCMethod("setGroupsByEvent:") func setGroupsByEvent(_ value: Bool) { groupsByEvent = value }
    @ObjCMethod("levelsOfUndo") func levelsOfUndo() -> Int { levels }
    @ObjCMethod("setLevelsOfUndo:") func setLevelsOfUndo(_ value: Int) { levels = max(0, value) }
    @ObjCMethod("runLoopModes") func runLoopModesValue() -> UnsafeMutableRawPointer? { runLoopModes }
    @ObjCMethod("setRunLoopModes:") func setRunLoopModes(_ modes: UnsafeMutableRawPointer?) {
        if let runLoopModes { ObjC.release(runLoopModes) }
        runLoopModes = modes.flatMap { ObjC.retain($0) }
    }

    // MARK: Registering

    /// The group an action goes in: the open one, or, when grouping by event,
    /// one opened for it and closed when the run loop next turns.
    private func currentGroup() -> UndoGroup {
        if open.isEmpty {
            beginUndoGrouping()
            if groupsByEvent { perform(ObjCSelector("_perryEndEventGroup"), with: nil, afterDelay: 0) }
        }
        return open[open.count - 1]
    }

    /// Closes the group opened for an event once the event is handled.
    @ObjCMethod("_perryEndEventGroup")
    func endEventGroup() {
        if groupsByEvent { while !open.isEmpty { endUndoGrouping() } }
    }

    private func register(_ action: UndoAction) {
        guard disabled == 0 else { return }
        currentGroup().actions.append(action)
        post("NSUndoManagerDidRegisterUndoNotification")
    }

    @ObjCMethod("registerUndoWithTarget:selector:object:")
    func registerUndo(target: UnsafeMutableRawPointer?, selector: ObjCSelector?, object: UnsafeMutableRawPointer?) {
        register(UndoAction(target: target, selector: selector, object: object, block: nil))
    }

    @ObjCMethod("registerUndoWithTarget:handler:")
    func registerUndo(target: UnsafeMutableRawPointer?, handler: UnsafeMutableRawPointer?) {
        register(UndoAction(target: target, selector: nil, object: nil, block: handler))
    }

    /// The manager itself, which records the next message it doesn't
    /// implement as an action sending that message to the target.
    @ObjCMethod("prepareWithInvocationTarget:")
    func prepare(invocationTarget: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        preparedTarget = invocationTarget
        return objcObject
    }

    /// The manager's own method's signature, or else the prepared target's.
    @ObjCMethod("methodSignatureForSelector:")
    func undoMethodSignature(for selector: ObjCSelector?) -> UnsafeMutableRawPointer? {
        let name = selector.map { $0.pointer.assumingMemoryBound(to: CChar.self) }
        if let own = MethodSignatures.of(ObjC.objectGetClass(objcObject), name) { return own }
        guard let target = preparedTarget, let name else { return nil }
        return ObjC.send(target, ObjC.selector("methodSignatureForSelector:"), UnsafeMutableRawPointer(mutating: name))
    }

    /// A message forwarded after -prepareWithInvocationTarget:, kept with its
    /// arguments as an action for the target.
    @ObjCMethod("forwardInvocation:")
    func recordForwardedInvocation(_ invocation: UnsafeMutableRawPointer?) {
        guard let invocation, let target = preparedTarget else { return }
        preparedTarget = nil
        _ = ObjC.send(invocation, ObjC.selector("setTarget:"), target)
        _ = ObjC.send(invocation, ObjC.selector("retainArguments"))
        register(UndoAction(target: target, selector: nil, object: nil, block: nil, invocation: invocation))
    }

    @ObjCMethod("disableUndoRegistration") func disableUndoRegistration() { disabled += 1 }
    @ObjCMethod("enableUndoRegistration") func enableUndoRegistration() { disabled = max(0, disabled - 1) }
    @ObjCMethod("isUndoRegistrationEnabled") func isUndoRegistrationEnabled() -> Bool { disabled == 0 }

    @ObjCMethod("removeAllActions")
    func removeAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        open.removeAll()
    }

    @ObjCMethod("removeAllActionsWithTarget:")
    func removeAllActions(target: UnsafeMutableRawPointer?) {
        for group in undoStack + redoStack + open { group.actions.removeAll { $0.target == target } }
        undoStack.removeAll { $0.actions.isEmpty }
        redoStack.removeAll { $0.actions.isEmpty }
    }

    // MARK: Undoing

    @ObjCMethod("canUndo") func canUndo() -> Bool { !undoStack.isEmpty || open.contains { !$0.actions.isEmpty } }
    @ObjCMethod("canRedo") func canRedo() -> Bool { !redoStack.isEmpty }
    @ObjCMethod("isUndoing") func isUndoing() -> Bool { undoing }
    @ObjCMethod("isRedoing") func isRedoing() -> Bool { redoing }

    /// Runs a group's actions, last first, inside a group of their own that
    /// collects what they register.
    private func run(_ group: UndoGroup) {
        beginUndoGrouping()
        open[open.count - 1].name = group.name
        for action in group.actions.reversed() { action.perform() }
        endUndoGrouping()
    }

    @ObjCMethod("undo")
    func undo() {
        while open.count > 0 { endUndoGrouping() }
        undoNestedGroup()
    }

    @ObjCMethod("undoNestedGroup")
    func undoNestedGroup() {
        guard let group = undoStack.popLast() else { return }
        post("NSUndoManagerWillUndoChangeNotification")
        undoing = true
        run(group)
        undoing = false
        post("NSUndoManagerDidUndoChangeNotification")
    }

    @ObjCMethod("redo")
    func redo() {
        guard let group = redoStack.popLast() else { return }
        post("NSUndoManagerWillRedoChangeNotification")
        redoing = true
        run(group)
        redoing = false
        post("NSUndoManagerDidRedoChangeNotification")
    }

    // MARK: Names

    @ObjCMethod("setActionName:")
    func setActionName(_ name: String?) {
        guard disabled == 0, let name, let group = open.last ?? undoStack.last else { return }
        group.name = name
    }

    /// The group being registered: the open one, or the last closed.
    private var namedGroup: UndoGroup? { open.last ?? undoStack.last }

    /// Marks the group being registered as discardable: one whose undoing
    /// changes nothing the user would miss (a selection, say).
    @ObjCMethod("setActionIsDiscardable:")
    func setActionIsDiscardable(_ discardable: Bool) { namedGroup?.discardable = discardable }

    @ObjCMethod("undoActionIsDiscardable") func undoActionIsDiscardable() -> Bool { undoStack.last?.discardable ?? false }
    @ObjCMethod("redoActionIsDiscardable") func redoActionIsDiscardable() -> Bool { redoStack.last?.discardable ?? false }

    /// iOS 18's values kept with the group being registered, by key.
    @ObjCMethod("setActionUserInfoValue:forKey:")
    func setActionUserInfoValue(_ value: UnsafeMutableRawPointer?, forKey key: String?) {
        guard let key, let group = namedGroup else { return }
        if let old = group.userInfo.removeValue(forKey: key) { ObjC.release(old) }
        if let value { group.userInfo[key] = ObjC.retain(value) }
    }

    @ObjCMethod("undoActionUserInfoValueForKey:")
    func undoActionUserInfoValue(forKey key: String?) -> UnsafeMutableRawPointer? { key.flatMap { undoStack.last?.userInfo[$0] } }

    @ObjCMethod("redoActionUserInfoValueForKey:")
    func redoActionUserInfoValue(forKey key: String?) -> UnsafeMutableRawPointer? { key.flatMap { redoStack.last?.userInfo[$0] } }

    /// The groups that can be undone and redone.
    @ObjCMethod("undoCount") func undoCount() -> UInt { UInt(undoStack.count) }
    @ObjCMethod("redoCount") func redoCount() -> UInt { UInt(redoStack.count) }

    @ObjCMethod("undoActionName") func undoActionName() -> String { undoStack.last?.name ?? "" }
    @ObjCMethod("redoActionName") func redoActionName() -> String { redoStack.last?.name ?? "" }
    @ObjCMethod("undoMenuItemTitle") func undoMenuItemTitle() -> String { undoMenuTitle(forUndoActionName: undoActionName()) }
    @ObjCMethod("redoMenuItemTitle") func redoMenuItemTitle() -> String { redoMenuTitle(forUndoActionName: redoActionName()) }

    @ObjCMethod("undoMenuTitleForUndoActionName:")
    func undoMenuTitle(forUndoActionName name: String) -> String { name.isEmpty ? "Undo" : "Undo " + name }

    @ObjCMethod("redoMenuTitleForUndoActionName:")
    func redoMenuTitle(forUndoActionName name: String) -> String { name.isEmpty ? "Redo" : "Redo " + name }
}
