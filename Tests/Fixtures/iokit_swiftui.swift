import SwiftUI
import IOKit
let service = IOServiceGetMatchingService(0, IOServiceMatching("IOPlatformExpertDevice"))
precondition(service != 0)
let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, nil, 0)!.takeRetainedValue()
let text = Text(String(describing: value))
print("SwiftUI Text created with IOKit identity: \(type(of: text))")
IOObjectRelease(service)
