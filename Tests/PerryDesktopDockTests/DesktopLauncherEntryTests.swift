import DBus
@testable import PerryDesktopDock
import Testing

/// `Update`'s properties, by name.
private func properties(_ state: DesktopLauncherEntry.State) -> [String: DBusMessageArgument] {
    let arguments = DesktopLauncherEntry.arguments(appURI: "application://com.example.Mail.desktop", state: state)
    guard arguments.count == 2, case let .dictionary(dictionary) = arguments[1] else { return [:] }
    var values: [String: DBusMessageArgument] = [:]
    for entry in dictionary {
        guard case let .string(key) = entry.key, case let .variant(variant) = entry.value else { continue }
        values[key] = variant.element
    }
    return values
}

@Test func appURINamesTheDesktopEntry() {
    let arguments = DesktopLauncherEntry.arguments(appURI: "application://com.example.Mail.desktop", state: .init())
    #expect(arguments.first == .string("application://com.example.Mail.desktop"))
}

@Test func badgeAndAttention() {
    let values = properties(.init(count: 7, urgent: true))
    #expect(values["count"] == .int64(7))
    #expect(values["count-visible"] == .boolean(true))
    #expect(values["progress-visible"] == .boolean(false))
    #expect(values["urgent"] == .boolean(true))
}

@Test func nothingShownSendsEveryPropertyOff() {
    // So a dock that missed an update still hears every property.
    let values = properties(.init())
    #expect(values["count-visible"] == .boolean(false))
    #expect(values["progress-visible"] == .boolean(false))
    #expect(values["urgent"] == .boolean(false))
}

@Test func progressIsClamped() {
    #expect(properties(.init(progress: 1.5))["progress"] == .double(1))
    #expect(properties(.init(progress: 0.25))["progress"] == .double(0.25))
}
