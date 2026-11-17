import CPerryGeometry
import PerryObjCInterop

// GameplayKit's states and state machines: a machine holds states, one of
// them the current, and moves between them as each allows, telling each as it
// leaves and enters. A machine updates its current state.

final class StateMachineState: ObjectState {
    var states: [NSObject] = []
    var current: NSObject?
}

final class GKStateState: ObjectState {
    /// The machine the state is in, which holds it; not retained.
    var machine: UnsafeMutableRawPointer?
}

extension NSObject {
    @ObjCMethod("isValidNextState:") func gkSendIsValidNextState(_ state: ObjCClass) -> Bool
    @ObjCMethod("didEnterWithPreviousState:") func gkSendDidEnter(previous: NSObject?)
    @ObjCMethod("willExitWithNextState:") func gkSendWillExit(next: NSObject?)
}

@ObjCClass("GKState")
open class GKState: NSObject {
    static let stateStates = StateTable<GKStateState>()
    var machineLink: GKStateState { GKState.stateStates[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        GKState.stateStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKState.objCClass.pointer)
    }

    @ObjCClassMethod("state") static func make(_ cls: ObjCClass) -> GKState { cls.object.allocated().initialized().unsafeCast(to: GKState.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    /// Any state may follow, unless a subclass says otherwise.
    @ObjCMethod("isValidNextState:") func isValidNextState(_ state: ObjCClass) -> Bool { true }
    @ObjCMethod("didEnterWithPreviousState:") func didEnter(previous: NSObject?) {}
    @ObjCMethod("willExitWithNextState:") func willExit(next: NSObject?) {}
    @ObjCMethod("updateWithDeltaTime:") func update(deltaTime seconds: Double) {}

    @ObjCMethod("stateMachine")
    func stateMachine() -> GKStateMachine? { machineLink.machine.map { GKStateMachine(objcObject: $0, ownership: .retain) } }
}

@ObjCClass("GKStateMachine")
open class GKStateMachine: NSObject {
    static let machineStates = StateTable<StateMachineState>()
    var machine: StateMachineState { GKStateMachine.machineStates[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        for state in machine.states { GKState.stateStates.existing(state.objcObject)?.machine = nil }
        GKStateMachine.machineStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKStateMachine.objCClass.pointer)
    }

    @ObjCClassMethod("stateMachineWithStates:")
    static func make(_ cls: ObjCClass, states: NSArray) -> GKStateMachine {
        let machine = cls.object.allocated().unsafeCast(to: GKStateMachine.self)
        return machine.initialize(states: states)
    }

    @ObjCMethod("initWithStates:")
    func initialize(states: NSArray) -> Self {
        machine.states = states.elements
        for state in machine.states { GKState.stateStates[state.objcObject].machine = objcObject }
        return self
    }

    @ObjCMethod("currentState") func currentState() -> NSObject? { machine.current }

    @ObjCMethod("stateForClass:")
    func state(forClass cls: ObjCClass) -> NSObject? {
        machine.states.first { ObjCRuntime.objectClass($0.objcObject) == cls.pointer }
    }

    @ObjCMethod("canEnterState:")
    func canEnter(_ cls: ObjCClass) -> Bool {
        guard state(forClass: cls) != nil else { return false }
        return machine.current?.gkSendIsValidNextState(cls) ?? true
    }

    /// Enters the state of the class, when it is one of the machine's and the
    /// current state allows it.
    @ObjCMethod("enterState:")
    func enter(_ cls: ObjCClass) -> Bool {
        guard canEnter(cls), let next = state(forClass: cls) else { return false }
        let previous = machine.current
        previous?.gkSendWillExit(next: next)
        machine.current = next
        next.gkSendDidEnter(previous: previous)
        return true
    }

    @ObjCMethod("updateWithDeltaTime:")
    func update(deltaTime seconds: Double) { machine.current?.gkSendUpdate(deltaTime: seconds) }
}
