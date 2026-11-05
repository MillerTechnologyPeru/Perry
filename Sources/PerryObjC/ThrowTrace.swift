import Glibc
import PerryInterface
import PerryObjCRuntime

/// With PERRY_SWIFT_THROW_TRACE set, every Swift error thrown is printed
/// with its description and the frames that threw it, through the Swift
/// runtime's _swift_willThrow hook: for an app that turns an error into a
/// message of its own. The error box is an Objective-C object, so it
/// describes itself as Swift's String(describing:) would.
enum ThrowTrace {
    /// The current task's name, when it has one: swift_task_getCurrentTaskName.
    nonisolated(unsafe) static var taskName: (@convention(c) () -> UnsafePointer<CChar>?)?

    static func install(_ lookup: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?) {
        guard getenv("PERRY_SWIFT_THROW_TRACE") != nil,
              let hook = "/usr/lib/swift/libswiftCore.dylib".withCString({ library in
                  "__swift_willThrow".withCString { lookup(library, $0) }
              }) else { return }
        typealias TaskName = @convention(c) () -> UnsafePointer<CChar>?
        taskName = "/usr/lib/swift/libswift_Concurrency.dylib".withCString { library in
            "_swift_task_getCurrentTaskName".withCString { lookup(library, $0) }
        }.map { unsafeBitCast($0, to: TaskName.self) }
        typealias WillThrow = @convention(c) (UnsafeMutableRawPointer?) -> Void
        let report: WillThrow = { error in
            let task = ThrowTrace.taskName?().map { " in task \"" + String(cString: $0) + "\"" } ?? ""
            let description = Messages.send(error, Selectors.register("description"))
            let text = Messages.send(description, Selectors.register("UTF8String"))
                .map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? "?"
            perry_print_frames("perry: swift: throw\(task) \(text.prefix(2000))")
        }
        hook.storeBytes(of: report, as: WillThrow.self)
    }
}
