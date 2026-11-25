import DBus
@testable import PerryDesktopNotifications
import Testing

@Test func notifyArgumentsRunActionsTogether() {
    let notification = DesktopNotifications.Notification(
        identifier: "reminder-1", appName: "Calendar", summary: "Lunch", body: "Noon at the café",
        actions: [.init(key: "snooze", label: "Snooze")]
    )
    let arguments = DesktopNotifications.notifyArguments(notification, replacing: 4)
    #expect(arguments.count == 8)
    #expect(arguments[0] == .string("Calendar"))
    #expect(arguments[1] == .uint32(4))
    #expect(arguments[3] == .string("Lunch"))
    #expect(arguments[4] == .string("Noon at the café"))
    guard case let .array(actions) = arguments[5] else {
        Issue.record("No actions")
        return
    }
    // The notification itself first, then the buttons.
    #expect(actions.map { $0 } == [.string("default"), .string(""), .string("snooze"), .string("Snooze")])
    #expect(arguments[7] == .int32(-1))
}

@Test func withoutADefaultActionOnlyButtons() {
    let notification = DesktopNotifications.Notification(identifier: "x", appName: "", summary: "Hi", hasDefaultAction: false)
    guard case let .array(actions) = DesktopNotifications.notifyArguments(notification, replacing: 0)[5] else {
        Issue.record("No actions")
        return
    }
    #expect(actions.isEmpty)
}
