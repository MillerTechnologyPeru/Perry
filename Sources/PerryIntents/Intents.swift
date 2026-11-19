import Glibc
import PerryObjCInterop

// Intents' classes. There is no Siri or Shortcuts here: intents and their
// responses are plain values an app makes and reads back, interactions are
// donated to nothing (successfully), voice shortcuts are none, and relevant
// shortcuts are kept by nobody. Nothing ever asks an app to handle an intent.

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

extension ObjCClass {
    /// The class object, as an object to send class messages to.
    var object: NSObject { NSObject(pointer) }
}

/// Calls a completion handler, `void (^)(NSError *)`, with no error.
private func complete(_ handler: ObjCBlock?) {
    guard let handler else { return }
    handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(handler.object, nil)
}

/// An empty NSArray.
private func emptyArray() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }

// MARK: - Intents

/// INIntent: what an app's subclasses and the system's intents share.
@ObjCClass("INIntent")
open class INIntent: NSObject {
    var identifier: String?
    var suggestedInvocationPhrase: String?
    var donationMetadata: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("identifier") func getIdentifier() -> String? { identifier }
    @ObjCMethod("intentDescription") func intentDescription() -> String? { nil }
    @ObjCMethod("suggestedInvocationPhrase") func getSuggestedInvocationPhrase() -> String? { suggestedInvocationPhrase }
    @ObjCMethod("setSuggestedInvocationPhrase:") func setSuggestedInvocationPhrase(_ phrase: String?) { suggestedInvocationPhrase = phrase }
    @ObjCMethod("shortcutAvailability") func shortcutAvailability() -> UInt { 0 }
    @ObjCMethod("setShortcutAvailability:") func setShortcutAvailability(_ availability: UInt) {}
    @ObjCMethod("donationMetadata") func getDonationMetadata() -> NSObject? { donationMetadata }
    @ObjCMethod("setDonationMetadata:") func setDonationMetadata(_ metadata: NSObject?) { donationMetadata = metadata }
    /// Images for parameters are not shown anywhere: none is kept.
    @ObjCMethod("setImage:forParameterNamed:") func setImage(_ image: NSObject?, forParameterNamed name: String?) {}
    @ObjCMethod("imageForParameterNamed:") func image(forParameterNamed name: String?) -> NSObject? { nil }
    @ObjCMethod("keyImage") func keyImage() -> NSObject? { nil }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// The system's intents an app makes to donate: their parameters are not
/// kept, as nothing reads them back here.
@ObjCClass("INPlayMediaIntent") open class INPlayMediaIntent: INIntent {
    @ObjCMethod("initWithMediaItems:mediaContainer:playShuffled:playbackRepeatMode:resumePlayback:playbackQueueLocation:playbackSpeed:mediaSearch:")
    func initialize(items: NSObject?, container: NSObject?, shuffled: NSObject?, repeatMode: Int, resume: NSObject?,
                    location: Int, speed: NSObject?, search: NSObject?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}
@ObjCClass("INSearchForMediaIntent") open class INSearchForMediaIntent: INIntent {
    @ObjCMethod("initWithMediaItems:mediaSearch:")
    func initialize(items: NSObject?, search: NSObject?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}
@ObjCClass("INSearchCallHistoryIntent") open class INSearchCallHistoryIntent: INIntent {}
@ObjCClass("INStartCallIntent") open class INStartCallIntent: INIntent {}
@ObjCClass("INStartAudioCallIntent") open class INStartAudioCallIntent: INIntent {}
@ObjCClass("INStartVideoCallIntent") open class INStartVideoCallIntent: INIntent {}
@ObjCClass("INSendMessageIntent") open class INSendMessageIntent: INIntent {}

@ObjCClass("INSendMessageIntentDonationMetadata")
open class INSendMessageIntentDonationMetadata: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }
}

/// INIntentResponse: an app's subclasses' responses, with a code and an activity.
@ObjCClass("INIntentResponse")
open class INIntentResponse: NSObject {
    var userActivity: NSObject?
    var code = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCode:userActivity:")
    func initialize(code: Int, userActivity: NSObject?) -> UnsafeMutableRawPointer? {
        self.code = code
        self.userActivity = userActivity
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("code") func getCode() -> Int { code }
    @ObjCMethod("setCode:") func setCode(_ code: Int) { self.code = code }
    @ObjCMethod("userActivity") func getUserActivity() -> NSObject? { userActivity }
    @ObjCMethod("setUserActivity:") func setUserActivity(_ activity: NSObject?) { userActivity = activity }
}

// MARK: - Interactions

/// INInteraction: an intent and its response, donated to nothing.
@ObjCClass("INInteraction")
open class INInteraction: NSObject {
    var intent: NSObject?
    var response: NSObject?
    var identifier: String?
    var groupIdentifier: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIntent:response:")
    func initialize(intent: NSObject?, response: NSObject?) -> UnsafeMutableRawPointer? {
        self.intent = intent
        self.response = response
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("intent") func getIntent() -> NSObject? { intent }
    @ObjCMethod("intentResponse") func intentResponse() -> NSObject? { response }
    @ObjCMethod("identifier") func getIdentifier() -> String? { identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ identifier: String?) { self.identifier = identifier }
    @ObjCMethod("groupIdentifier") func getGroupIdentifier() -> String? { groupIdentifier }
    @ObjCMethod("setGroupIdentifier:") func setGroupIdentifier(_ identifier: String?) { groupIdentifier = identifier }
    @ObjCMethod("direction") func direction() -> Int { 0 }
    @ObjCMethod("setDirection:") func setDirection(_ direction: Int) {}
    @ObjCMethod("dateInterval") func dateInterval() -> NSObject? { nil }
    @ObjCMethod("setDateInterval:") func setDateInterval(_ interval: NSObject?) {}

    @ObjCMethod("donateInteractionWithCompletion:") func donate(completion: ObjCBlock?) { complete(completion) }
    @ObjCClassMethod("deleteAllInteractionsWithCompletion:") static func deleteAll(completion: ObjCBlock?) { complete(completion) }
    @ObjCClassMethod("deleteInteractionsWithIdentifiers:completion:")
    static func delete(identifiers: NSObject?, completion: ObjCBlock?) { complete(completion) }
    @ObjCClassMethod("deleteInteractionsWithGroupIdentifier:completion:")
    static func delete(groupIdentifier: String?, completion: ObjCBlock?) { complete(completion) }
}

// MARK: - Values

/// INImage: an image for an intent, by name, data or URL; kept, not shown.
@ObjCClass("INImage")
open class INImage: NSObject {
    var name: String?
    var data: NSObject?
    var url: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    private static func make(_ set: (INImage) -> Void) -> NSObject {
        let image = objCClass.object.newInstance().unsafeCast(to: INImage.self)
        set(image)
        return image
    }
    @ObjCClassMethod("imageNamed:") static func named(_ name: String?) -> NSObject { make { $0.name = name } }
    @ObjCClassMethod("systemImageNamed:") static func systemNamed(_ name: String?) -> NSObject { make { $0.name = name } }
    @ObjCClassMethod("imageWithImageData:") static func with(data: NSObject?) -> NSObject { make { $0.data = data } }
    @ObjCClassMethod("imageWithURL:") static func with(url: NSObject?) -> NSObject { make { $0.url = url } }
    @ObjCClassMethod("imageWithURL:width:height:")
    static func with(url: NSObject?, width: Double, height: Double) -> NSObject { make { $0.url = url } }
    @ObjCClassMethod("imageWithUIImage:") static func with(image: NSObject?) -> NSObject { make { _ in } }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// INSpeakableString: text Siri would speak, with an identifier.
@ObjCClass("INSpeakableString")
open class INSpeakableString: NSObject {
    var spoken: String?
    var identifier: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithSpokenPhrase:")
    func initialize(spokenPhrase: String?) -> UnsafeMutableRawPointer? {
        spoken = spokenPhrase
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("initWithVocabularyIdentifier:spokenPhrase:pronunciationHint:")
    func initialize(identifier: String?, spokenPhrase: String?, hint: String?) -> UnsafeMutableRawPointer? {
        self.identifier = identifier
        spoken = spokenPhrase
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("spokenPhrase") func spokenPhrase() -> String { spoken ?? "" }
    @ObjCMethod("vocabularyIdentifier") func vocabularyIdentifier() -> String? { identifier }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// INPersonHandle: an address, phone number or other way to reach someone.
@ObjCClass("INPersonHandle")
open class INPersonHandle: NSObject {
    var value: String?
    var type = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithValue:type:")
    func initialize(value: String?, type: Int) -> UnsafeMutableRawPointer? {
        self.value = value
        self.type = type
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("initWithValue:type:label:")
    func initialize(value: String?, type: Int, label: String?) -> UnsafeMutableRawPointer? { initialize(value: value, type: type) }
    @ObjCMethod("value") func getValue() -> String? { value }
    @ObjCMethod("type") func getType() -> Int { type }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// INPerson: someone an intent is about, by handle and name.
@ObjCClass("INPerson")
open class INPerson: NSObject {
    var handle: NSObject?
    var displayName = ""

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithPersonHandle:nameComponents:displayName:image:contactIdentifier:customIdentifier:")
    func initialize(handle: NSObject?, nameComponents: NSObject?, displayName: String?, image: NSObject?,
                    contactIdentifier: String?, customIdentifier: String?) -> UnsafeMutableRawPointer? {
        self.handle = handle
        self.displayName = displayName ?? ""
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("initWithPersonHandle:nameComponents:displayName:image:contactIdentifier:customIdentifier:isMe:")
    func initialize(handle: NSObject?, nameComponents: NSObject?, displayName: String?, image: NSObject?,
                    contactIdentifier: String?, customIdentifier: String?, isMe: Bool) -> UnsafeMutableRawPointer? {
        initialize(handle: handle, nameComponents: nameComponents, displayName: displayName, image: image,
                   contactIdentifier: contactIdentifier, customIdentifier: customIdentifier)
    }
    @ObjCMethod("personHandle") func personHandle() -> NSObject? { handle }
    @ObjCMethod("displayName") func getDisplayName() -> String { displayName }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// INMediaItem: a song, episode or other media an intent names.
@ObjCClass("INMediaItem")
open class INMediaItem: NSObject {
    var identifier: String?
    var title: String?
    var type = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:title:type:artwork:")
    func initialize(identifier: String?, title: String?, type: Int, artwork: NSObject?) -> UnsafeMutableRawPointer? {
        (self.identifier, self.title, self.type) = (identifier, title, type)
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("initWithIdentifier:title:type:artwork:artist:")
    func initialize(identifier: String?, title: String?, type: Int, artwork: NSObject?, artist: String?) -> UnsafeMutableRawPointer? {
        initialize(identifier: identifier, title: title, type: type, artwork: artwork)
    }
    @ObjCMethod("identifier") func getIdentifier() -> String? { identifier }
    @ObjCMethod("title") func getTitle() -> String? { title }
    @ObjCMethod("type") func getType() -> Int { type }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

// MARK: - Shortcuts

/// INShortcut: an intent or activity an app suggests as a shortcut.
@ObjCClass("INShortcut")
open class INShortcut: NSObject {
    var intent: NSObject?
    var userActivity: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIntent:")
    func initialize(intent: NSObject?) -> UnsafeMutableRawPointer? {
        self.intent = intent
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("initWithUserActivity:")
    func initialize(userActivity: NSObject?) -> UnsafeMutableRawPointer? {
        self.userActivity = userActivity
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("intent") func getIntent() -> NSObject? { intent }
    @ObjCMethod("userActivity") func getUserActivity() -> NSObject? { userActivity }
}

/// INRelevantShortcut: a shortcut with when it would be relevant.
@ObjCClass("INRelevantShortcut")
open class INRelevantShortcut: NSObject {
    var shortcut: NSObject?
    var relevanceProviders: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithShortcut:")
    func initialize(shortcut: NSObject?) -> UnsafeMutableRawPointer? {
        self.shortcut = shortcut
        return ObjCRuntime.retain(objcObject)
    }
    @ObjCMethod("shortcut") func getShortcut() -> NSObject? { shortcut }
    @ObjCMethod("relevanceProviders") func getRelevanceProviders() -> NSObject { relevanceProviders ?? emptyArray() }
    @ObjCMethod("setRelevanceProviders:") func setRelevanceProviders(_ providers: NSObject?) { relevanceProviders = providers }
    @ObjCMethod("shortcutRole") func shortcutRole() -> Int { 0 }
    @ObjCMethod("setShortcutRole:") func setShortcutRole(_ role: Int) {}
    @ObjCMethod("watchTemplate") func watchTemplate() -> NSObject? { nil }
    @ObjCMethod("setWatchTemplate:") func setWatchTemplate(_ template: NSObject?) {}
}

@ObjCClass("INRelevanceProvider")
open class INRelevanceProvider: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }
}

@ObjCClass("INDateRelevanceProvider")
open class INDateRelevanceProvider: INRelevanceProvider {
    @ObjCMethod("initWithStartDate:endDate:")
    func initialize(start: NSObject?, end: NSObject?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

/// INRelevantShortcutStore: relevant shortcuts are taken and not kept.
@ObjCClass("INRelevantShortcutStore")
open class INRelevantShortcutStore: NSObject {
    nonisolated(unsafe) static var store: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("defaultStore")
    static func defaultStore() -> NSObject {
        if let store { return store }
        let made = objCClass.object.newInstance()
        store = made
        return made
    }
    @ObjCMethod("setRelevantShortcuts:completionHandler:")
    func setRelevantShortcuts(_ shortcuts: NSObject?, completion: ObjCBlock?) { complete(completion) }
}

/// INVoiceShortcutCenter: the user's voice shortcuts, of which there are none.
@ObjCClass("INVoiceShortcutCenter")
open class INVoiceShortcutCenter: NSObject {
    nonisolated(unsafe) static var center: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedCenter")
    static func sharedCenter() -> NSObject {
        if let center { return center }
        let made = objCClass.object.newInstance()
        center = made
        return made
    }
    /// Calls `void (^)(NSArray *, NSError *)` with no shortcuts.
    @ObjCMethod("getAllVoiceShortcutsWithCompletion:")
    func getAll(completion: ObjCBlock?) {
        guard let completion else { return }
        let none = emptyArray()
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        withExtendedLifetime(none) { completion.function(as: Invoke.self)(completion.object, none.objcObject, nil) }
    }
    /// Calls `void (^)(INVoiceShortcut *, NSError *)` with none.
    @ObjCMethod("getVoiceShortcutWithIdentifier:completion:")
    func get(identifier: NSObject?, completion: ObjCBlock?) {
        guard let completion else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        completion.function(as: Invoke.self)(completion.object, nil, nil)
    }
    @ObjCMethod("setShortcutSuggestions:") func setShortcutSuggestions(_ suggestions: NSObject?) {}
}
