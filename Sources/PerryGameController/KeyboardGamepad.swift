import CSDL3
import Glibc

// The keyboard as a gamepad: with PERRY_GAMECONTROLLER_KEYBOARD set, an SDL
// virtual gamepad named "Keyboard" is attached when the gamepads start, and
// the keys held set its buttons and sticks each time they are read, so it
// connects and reads as any other controller does. The keys:
//
//   W A S D          left stick         I J K L        right stick
//   arrow keys       direction pad      Space, Return  A
//   Left Shift       B                  F              X
//   R                Y                  Q, E           left, right shoulder
//   Z, C             left, right trigger X, V           left, right stick button
//   Escape           Menu               Tab            Options
enum KeyboardGamepad {
    nonisolated(unsafe) static let enabled = getenv("PERRY_GAMECONTROLLER_KEYBOARD") != nil
    nonisolated(unsafe) private static var joystick: OpaquePointer?
    /// The scancodes held at the last read, for tracing.
    nonisolated(unsafe) private static var heldKeys: [Int] = []

    /// SDL_GamepadButton's order: the buttons a virtual gamepad with no
    /// button mask has, and the keys that press each.
    private static let buttons: [[SDL_Scancode]] = [
        [SDL_SCANCODE_SPACE, SDL_SCANCODE_RETURN],  // south: A
        [SDL_SCANCODE_LSHIFT],                      // east: B
        [SDL_SCANCODE_F],                           // west: X
        [SDL_SCANCODE_R],                           // north: Y
        [SDL_SCANCODE_TAB],                         // back: Options
        [],                                         // guide: Home
        [SDL_SCANCODE_ESCAPE],                      // start: Menu
        [SDL_SCANCODE_X],                           // left stick
        [SDL_SCANCODE_V],                           // right stick
        [SDL_SCANCODE_Q],                           // left shoulder
        [SDL_SCANCODE_E],                           // right shoulder
        [SDL_SCANCODE_UP],
        [SDL_SCANCODE_DOWN],
        [SDL_SCANCODE_LEFT],
        [SDL_SCANCODE_RIGHT],
    ]

    /// Attaches and opens the virtual gamepad, once the gamepad subsystem
    /// is up.
    static func attach() {
        guard enabled, joystick == nil else { return }
        var description = SDL_VirtualJoystickDesc()
        description.version = UInt32(MemoryLayout<SDL_VirtualJoystickDesc>.size)
        description.type = UInt16(SDL_JOYSTICK_TYPE_GAMEPAD.rawValue)
        description.naxes = 6
        description.nbuttons = UInt16(buttons.count)
        let id = "Keyboard".withCString { name -> SDL_JoystickID in
            description.name = name
            return SDL_AttachVirtualJoystick(&description)
        }
        guard id != 0, let opened = SDL_OpenJoystick(id) else {
            Controllers.trace("the keyboard's gamepad couldn't be attached: \(String(cString: SDL_GetError()))")
            return
        }
        joystick = opened
        Controllers.trace("the keyboard is a gamepad")
    }

    /// Sets the virtual gamepad from the keys held now, before the gamepads
    /// are read.
    static func update() {
        guard let joystick else { return }
        var count: Int32 = 0
        guard let keys = SDL_GetKeyboardState(&count) else { return }
        func held(_ key: SDL_Scancode) -> Bool { keys[Int(key.rawValue)] }
        if Controllers.tracing {
            let down = (0..<Int(count)).filter { keys[$0] }
            if down != heldKeys {
                heldKeys = down
                let focus = SDL_GetKeyboardFocus()
                Controllers.trace("keys held: \(down), keyboard focus \(String(describing: focus)), text input \(focus.map { SDL_TextInputActive($0) } ?? false)")
            }
        }
        for (index, keysForButton) in buttons.enumerated() {
            SDL_SetJoystickVirtualButton(joystick, Int32(index), keysForButton.contains(where: held))
        }
        /// An axis from the keys for its two ends, as SDL has it: right and
        /// down positive.
        func axis(_ negative: SDL_Scancode, _ positive: SDL_Scancode) -> Int16 {
            (held(positive) ? Int16.max : 0) - (held(negative) ? Int16.max : 0)
        }
        let axes: [Int16] = [
            axis(SDL_SCANCODE_A, SDL_SCANCODE_D), axis(SDL_SCANCODE_W, SDL_SCANCODE_S),
            axis(SDL_SCANCODE_J, SDL_SCANCODE_L), axis(SDL_SCANCODE_I, SDL_SCANCODE_K),
            held(SDL_SCANCODE_Z) ? Int16.max : Int16.min, held(SDL_SCANCODE_C) ? Int16.max : Int16.min,
        ]
        for (index, value) in axes.enumerated() { SDL_SetJoystickVirtualAxis(joystick, Int32(index), value) }
    }
}
