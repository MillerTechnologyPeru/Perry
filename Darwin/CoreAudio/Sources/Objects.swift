import Foundation

// The audio hardware's API is macOS's alone.
#if os(macOS)

// The audio hardware's objects as classes, each property a selector of
// AudioHardware.h read or written with AudioObjectGetPropertyData and
// AudioObjectSetPropertyData.

/// The class of the object `id` is, by the Core Audio class it reports.
func audioObject(_ id: AudioObjectID) -> AudioHardwareObject {
    if id == kAudioObjectSystemObject {
        return AudioHardwareSystem.shared
    }
    let properties = Properties(id: id)
    let classID = (try? properties.get(global(kAudioObjectPropertyClass), AudioClassID(0))) ?? 0
    let baseClassID = (try? properties.get(global(kAudioObjectPropertyBaseClass), AudioClassID(0))) ?? 0
    switch classID {
    case kAudioAggregateDeviceClassID: return AudioHardwareAggregateDevice(id: id)
    case kAudioDeviceClassID, kAudioEndPointDeviceClassID, kAudioEndPointClassID, kAudioSubDeviceClassID: return AudioHardwareDevice(id: id)
    case kAudioClockDeviceClassID: return AudioHardwareClock(id: id)
    case kAudioBoxClassID: return AudioHardwareBox(id: id)
    case kAudioPlugInClassID, kAudioTransportManagerClassID: return AudioHardwarePlugin(id: id)
    case kAudioStreamClassID: return AudioHardwareStream(id: id)
    case kAudioProcessClassID: return AudioHardwareProcess(id: id)
    case kAudioTapClassID, kAudioSubTapClassID: return AudioHardwareTap(id: id)
    default: break
    }
    switch baseClassID {
    case kAudioDeviceClassID, kAudioAggregateDeviceClassID: return AudioHardwareDevice(id: id)
    case kAudioPlugInClassID: return AudioHardwarePlugin(id: id)
    case kAudioObjectClassID where classID == kAudioControlClassID: return AudioHardwareControl(id: id)
    default: break
    }
    // Controls have many classes, each derived from a control class.
    if baseClassID == kAudioControlClassID || [kAudioLevelControlClassID, kAudioBooleanControlClassID, kAudioSelectorControlClassID,
                                               kAudioSliderControlClassID, kAudioStereoPanControlClassID].contains(baseClassID) {
        return AudioHardwareControl(id: id)
    }
    return AudioHardwareObject(id: id)
}

func makeDevice(_ id: AudioObjectID) -> AudioHardwareDevice {
    audioObject(id) as? AudioHardwareDevice ?? AudioHardwareDevice(id: id)
}

func makeClock(_ id: AudioObjectID) -> AudioHardwareClock {
    audioObject(id) as? AudioHardwareClock ?? AudioHardwareClock(id: id)
}

/// A system translation of a UID to an object, nil for none.
private func system(_ selector: AudioObjectPropertySelector, _ uid: String) throws -> AudioObjectID? {
    try Properties(id: AudioObjectID(kAudioObjectSystemObject)).translate(global(selector), uid)
}

/// The clock or device of a UID.
func clockOrDevice(uid: String) throws -> AudioHardwareClock? {
    if let id = try system(kAudioHardwarePropertyTranslateUIDToDevice, uid) {
        return makeDevice(id)
    }
    return try system(kAudioHardwarePropertyTranslateUIDToClockDevice, uid).map(makeClock)
}

/// A listener block registered for an address on a queue.
private struct Listener {
    let address: AudioObjectPropertyAddress
    let queue: DispatchQueue?
    let block: AudioObjectPropertyListenerBlock
}

open class AudioHardwareObject: @unchecked Sendable {
    public final let id: AudioObjectID

    var properties: Properties { Properties(id: id) }

    private let lock = NSLock()
    private var storedDelegates: [any PropertyListenerDelegate] = []
    private var listeners: [Listener] = []

    /// Who's told of changes to the properties listened for.
    public var delegates: [any PropertyListenerDelegate] {
        get { lock.withLock { storedDelegates } }
        set(newDelegates) { lock.withLock { storedDelegates = newDelegates } }
    }

    open var baseClassID: AudioClassID {
        get throws { try properties.get(global(kAudioObjectPropertyBaseClass), AudioClassID(0)) }
    }

    open var classID: AudioClassID {
        get throws { try properties.get(global(kAudioObjectPropertyClass), AudioClassID(0)) }
    }

    open var owner: AudioHardwareObject? {
        get throws {
            let owner = try properties.get(global(kAudioObjectPropertyOwner), AudioObjectID(kAudioObjectUnknown))
            return owner == kAudioObjectUnknown ? nil : audioObject(owner)
        }
    }

    open var name: String {
        get throws { try properties.string(global(kAudioObjectPropertyName)) }
    }

    open var modelName: String {
        get throws { try properties.string(global(kAudioObjectPropertyModelName)) }
    }

    open var manufacturer: String {
        get throws { try properties.string(global(kAudioObjectPropertyManufacturer)) }
    }

    open var ownedObjects: [AudioHardwareObject] {
        get throws { try properties.ids(global(kAudioObjectPropertyOwnedObjects)).map(audioObject) }
    }

    open var isIdentifying: Bool {
        get throws { try properties.bool(global(kAudioObjectPropertyIdentify)) }
    }

    open var serialNumber: String {
        get throws { try properties.string(global(kAudioObjectPropertySerialNumber)) }
    }

    open var firmwareVersion: String {
        get throws { try properties.string(global(kAudioObjectPropertyFirmwareVersion)) }
    }

    open var creatorBundleID: String {
        get throws { try properties.string(global(kAudioObjectPropertyCreator)) }
    }

    open func setName(_ name: String) throws {
        try properties.setObject(global(kAudioObjectPropertyName), name as CFString)
    }

    open func setIsIdentifying(_ isIdentifying: Bool) throws {
        try properties.setBool(global(kAudioObjectPropertyIdentify), isIdentifying)
    }

    open func setCreatorBundleID(_ ID: String) throws {
        try properties.setObject(global(kAudioObjectPropertyCreator), ID as CFString)
    }

    public init(id: AudioObjectID) {
        self.id = id
    }

    open func hasProperty(address: AudioObjectPropertyAddress) -> Bool {
        properties.has(address)
    }

    open func isPropertySettable(address: AudioObjectPropertyAddress) throws -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(id, &address, &settable))
        return settable.boolValue
    }

    open func propertyDataSize(address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> Int {
        try properties.size(address, qualifier: qualifier)
    }

    open func propertyData(address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> Data {
        try properties.data(address, qualifier: qualifier)
    }

    open func setPropertyData(address: AudioObjectPropertyAddress, qualifier: Data? = nil, data: Data) throws {
        try properties.setData(address, qualifier: qualifier, data)
    }

    /// Sets the property and reads back what it then is, the device having
    /// applied it (the value it took may differ from the one asked for).
    open func setPropertyData(address: AudioObjectPropertyAddress, qualifier: Data? = nil, data: inout Data) async throws {
        try properties.setData(address, qualifier: qualifier, data)
        if let current = try? properties.data(address, qualifier: qualifier) {
            data = current
        }
    }

    /// Tells the delegates of changes to these properties, on `dispatchQueue`
    /// (Core Audio's own thread when nil).
    open func addListener(forProperties properties: [AudioObjectPropertyAddress], dispatchQueue: dispatch_queue_t? = nil) throws {
        for address in properties {
            let block: AudioObjectPropertyListenerBlock = { [weak self] count, addresses in
                guard let self else { return }
                let changed = Array(UnsafeBufferPointer(start: addresses, count: Int(count)))
                for delegate in self.delegates {
                    delegate.propertiesChanged(properties: changed)
                }
            }
            var address = address
            try check(AudioObjectAddPropertyListenerBlock(id, &address, dispatchQueue, block))
            lock.withLock { listeners.append(Listener(address: address, queue: dispatchQueue, block: block)) }
        }
    }

    open func removeListener(forProperties properties: [AudioObjectPropertyAddress], dispatchQueue: dispatch_queue_t? = nil) throws {
        for address in properties {
            let removed: [Listener] = lock.withLock {
                let matching = listeners.filter { $0.address == address && $0.queue === dispatchQueue }
                listeners.removeAll { $0.address == address && $0.queue === dispatchQueue }
                return matching
            }
            for listener in removed {
                var address = address
                try check(AudioObjectRemovePropertyListenerBlock(id, &address, dispatchQueue, listener.block))
            }
        }
    }

    deinit {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(id, &address, listener.queue, listener.block)
        }
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareSystem: AudioHardwareObject, @unchecked Sendable {
    public static let shared = AudioHardwareSystem(id: AudioObjectID(kAudioObjectSystemObject))

    open var devices: [AudioHardwareDevice] {
        get throws { try properties.ids(global(kAudioHardwarePropertyDevices)).map(makeDevice) }
    }

    open var plugins: [AudioHardwarePlugin] {
        get throws { try properties.ids(global(kAudioHardwarePropertyPlugInList)).map(AudioHardwarePlugin.init) }
    }

    open var boxes: [AudioHardwareBox] {
        get throws { try properties.ids(global(kAudioHardwarePropertyBoxList)).map(AudioHardwareBox.init) }
    }

    open var clocks: [AudioHardwareClock] {
        get throws { try properties.ids(global(kAudioHardwarePropertyClockDeviceList)).map(makeClock) }
    }

    open var processes: [AudioHardwareProcess] {
        get throws { try properties.ids(global(kAudioHardwarePropertyProcessObjectList)).map(AudioHardwareProcess.init) }
    }

    open var taps: [AudioHardwareTap] {
        get throws { try properties.ids(global(kAudioHardwarePropertyTapList)).map(AudioHardwareTap.init) }
    }

    private func defaultDevice(_ selector: AudioObjectPropertySelector) throws -> AudioHardwareDevice? {
        let id = try properties.get(global(selector), AudioObjectID(kAudioObjectUnknown))
        return id == kAudioObjectUnknown ? nil : makeDevice(id)
    }

    open var defaultInputDevice: AudioHardwareDevice? {
        get throws { try defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }
    }

    open var defaultOutputDevice: AudioHardwareDevice? {
        get throws { try defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
    }

    open var defaultSoundEffectsDevice: AudioHardwareDevice? {
        get throws { try defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) }
    }

    open var shouldMixStereoToMono: Bool {
        get throws { try properties.bool(global(kAudioHardwarePropertyMixStereoToMono)) }
    }

    open var isInitializingOrExiting: Bool {
        get throws { try properties.bool(global(kAudioHardwarePropertyIsInitingOrExiting)) }
    }

    open var isProcessInputMuted: Bool {
        get throws { try properties.bool(global(kAudioHardwarePropertyProcessInputMute)) }
    }

    open var allowsSleeping: Bool {
        get throws { try properties.bool(global(kAudioHardwarePropertySleepingIsAllowed)) }
    }

    open var allowsUnloading: Bool {
        get throws { try properties.bool(global(kAudioHardwarePropertyUnloadingIsAllowed)) }
    }

    open var allowsHogMode: Bool {
        get throws { try properties.bool(global(kAudioHardwarePropertyHogModeIsAllowed)) }
    }

    open var powerHint: AudioHardwarePowerHint {
        get throws {
            let value = try properties.get(global(kAudioHardwarePropertyPowerHint), UInt32(0))
            return AudioHardwarePowerHint(rawValue: value) ?? .none
        }
    }

    open func setDefaultInputDevice(_ device: AudioHardwareDevice) throws {
        try properties.set(global(kAudioHardwarePropertyDefaultInputDevice), device.id)
    }

    open func setDefaultOutputDevice(_ device: AudioHardwareDevice) throws {
        try properties.set(global(kAudioHardwarePropertyDefaultOutputDevice), device.id)
    }

    open func setDefaultSoundEffectsDevice(_ device: AudioHardwareDevice) throws {
        try properties.set(global(kAudioHardwarePropertyDefaultSystemOutputDevice), device.id)
    }

    open func setShouldMixStereoToMono(_ doMix: Bool) throws {
        try properties.setBool(global(kAudioHardwarePropertyMixStereoToMono), doMix)
    }

    open func setIsProcessInputMuted(_ muted: Bool) throws {
        try properties.setBool(global(kAudioHardwarePropertyProcessInputMute), muted)
    }

    open func setAllowsSleeping(_ allowed: Bool) throws {
        try properties.setBool(global(kAudioHardwarePropertySleepingIsAllowed), allowed)
    }

    open func setAllowsUnloading(_ allowed: Bool) throws {
        try properties.setBool(global(kAudioHardwarePropertyUnloadingIsAllowed), allowed)
    }

    open func setAllowsHogMode(_ allowed: Bool) throws {
        try properties.setBool(global(kAudioHardwarePropertyHogModeIsAllowed), allowed)
    }

    open func setPowerHint(_ hint: AudioHardwarePowerHint) throws {
        try properties.set(global(kAudioHardwarePropertyPowerHint), hint.rawValue)
    }

    open func unload() throws {
        try check(AudioHardwareUnload())
    }

    open func makeAggregateDevice(description: [String: Any]) throws -> AudioHardwareAggregateDevice? {
        var id = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &id))
        return id == kAudioObjectUnknown ? nil : AudioHardwareAggregateDevice(id: id)
    }

    open func destroyAggregateDevice(_ device: AudioHardwareAggregateDevice) throws {
        try check(AudioHardwareDestroyAggregateDevice(device.id))
    }

    open func makeProcessTap(description: CATapDescription) throws -> AudioHardwareTap? {
        var id = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &id))
        return id == kAudioObjectUnknown ? nil : AudioHardwareTap(id: id)
    }

    open func destroyProcessTap(_ tap: AudioHardwareTap) throws {
        try check(AudioHardwareDestroyProcessTap(tap.id))
    }

    open func device(forUID UID: String) throws -> AudioHardwareDevice? {
        try properties.translate(global(kAudioHardwarePropertyTranslateUIDToDevice), UID).map(makeDevice)
    }

    open func clock(forUID UID: String) throws -> AudioHardwareClock? {
        try properties.translate(global(kAudioHardwarePropertyTranslateUIDToClockDevice), UID).map(makeClock)
    }

    open func box(forUID UID: String) throws -> AudioHardwareBox? {
        try properties.translate(global(kAudioHardwarePropertyTranslateUIDToBox), UID).map(AudioHardwareBox.init)
    }

    open func tap(forUID UID: String) throws -> AudioHardwareTap? {
        try properties.translate(global(kAudioHardwarePropertyTranslateUIDToTap), UID).map(AudioHardwareTap.init)
    }

    open func plugin(forBundleID ID: String) throws -> AudioHardwarePlugin? {
        try properties.translate(global(kAudioHardwarePropertyTranslateBundleIDToPlugIn), ID).map(AudioHardwarePlugin.init)
    }

    open func process(for PID: pid_t) throws -> AudioHardwareProcess? {
        let id = try properties.get(global(kAudioHardwarePropertyTranslatePIDToProcessObject), qualifier: qualifier(PID), AudioObjectID(kAudioObjectUnknown))
        return id == kAudioObjectUnknown ? nil : AudioHardwareProcess(id: id)
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareStream: AudioHardwareObject, @unchecked Sendable {
    open var isActive: Bool {
        get throws { try properties.bool(global(kAudioStreamPropertyIsActive)) }
    }

    open var direction: AudioHardwareDirection {
        get throws { AudioHardwareDirection(rawValue: try properties.get(global(kAudioStreamPropertyDirection), UInt32(0))) ?? .output }
    }

    open var terminalType: UInt32 {
        get throws { try properties.get(global(kAudioStreamPropertyTerminalType), UInt32(0)) }
    }

    open var startingChannel: Int {
        get throws { try properties.int(global(kAudioStreamPropertyStartingChannel)) }
    }

    open var latency: Int {
        get throws { try properties.int(global(kAudioStreamPropertyLatency)) }
    }

    open var virtualFormat: AudioStreamBasicDescription {
        get throws { try properties.get(global(kAudioStreamPropertyVirtualFormat), AudioStreamBasicDescription()) }
    }

    open var availableVirtualFormats: [AudioStreamRangedDescription] {
        get throws { try properties.array(global(kAudioStreamPropertyAvailableVirtualFormats), of: AudioStreamRangedDescription.self) }
    }

    open var physicalFormat: AudioStreamBasicDescription {
        get throws { try properties.get(global(kAudioStreamPropertyPhysicalFormat), AudioStreamBasicDescription()) }
    }

    open var availablePhysicalFormats: [AudioStreamRangedDescription] {
        get throws { try properties.array(global(kAudioStreamPropertyAvailablePhysicalFormats), of: AudioStreamRangedDescription.self) }
    }

    open func setIsActive(_ active: Bool) throws {
        try properties.setBool(global(kAudioStreamPropertyIsActive), active)
    }

    open func setVirtualFormat(_ format: AudioStreamBasicDescription) throws {
        try properties.set(global(kAudioStreamPropertyVirtualFormat), format)
    }

    open func setPhysicalFormat(_ format: AudioStreamBasicDescription) throws {
        try properties.set(global(kAudioStreamPropertyPhysicalFormat), format)
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareProcess: AudioHardwareObject, @unchecked Sendable {
    open var pid: pid_t {
        get throws { try properties.get(global(kAudioProcessPropertyPID), pid_t(0)) }
    }

    open var bundleID: String? {
        get throws { try properties.object(global(kAudioProcessPropertyBundleID)) as? String }
    }

    open var devices: [AudioHardwareDevice] {
        get throws { try properties.ids(global(kAudioProcessPropertyDevices)).map(makeDevice) }
    }

    open var isRunning: Bool {
        get throws { try properties.bool(global(kAudioProcessPropertyIsRunning)) }
    }

    open var isRunningInput: Bool {
        get throws { try properties.bool(global(kAudioProcessPropertyIsRunningInput)) }
    }

    open var isRunningOutput: Bool {
        get throws { try properties.bool(global(kAudioProcessPropertyIsRunningOutput)) }
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareBox: AudioHardwareObject, @unchecked Sendable {
    open var uid: String {
        get throws { try properties.string(global(kAudioBoxPropertyBoxUID)) }
    }

    open var transportType: UInt32 {
        get throws { try properties.get(global(kAudioBoxPropertyTransportType), UInt32(0)) }
    }

    open var hasAudio: Bool {
        get throws { try properties.bool(global(kAudioBoxPropertyHasAudio)) }
    }

    open var hasVideo: Bool {
        get throws { try properties.bool(global(kAudioBoxPropertyHasVideo)) }
    }

    open var hasMIDI: Bool {
        get throws { try properties.bool(global(kAudioBoxPropertyHasMIDI)) }
    }

    open var isProtected: Bool {
        get throws { try properties.bool(global(kAudioBoxPropertyIsProtected)) }
    }

    /// Whether the box is acquired: its devices are in use.
    open var enabled: Bool {
        get throws { try properties.bool(global(kAudioBoxPropertyAcquired)) }
    }

    open var devices: [AudioHardwareDevice] {
        get throws { try properties.ids(global(kAudioBoxPropertyDeviceList)).map(makeDevice) }
    }

    open var clocks: [AudioHardwareClock] {
        get throws { try properties.ids(global(kAudioBoxPropertyClockDeviceList)).map(makeClock) }
    }

    open func enable() throws {
        try properties.setBool(global(kAudioBoxPropertyAcquired), true)
    }

    open func disable() throws {
        try properties.setBool(global(kAudioBoxPropertyAcquired), false)
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareControl: AudioHardwareObject, @unchecked Sendable {
    open var scope: AudioObjectPropertyScope {
        get throws { try properties.get(global(kAudioControlPropertyScope), AudioObjectPropertyScope(0)) }
    }

    open var element: AudioObjectPropertyElement {
        get throws { try properties.get(global(kAudioControlPropertyElement), AudioObjectPropertyElement(0)) }
    }

    open var sliderValue: UInt32 {
        get throws { try properties.get(global(kAudioSliderControlPropertyValue), UInt32(0)) }
    }

    open var sliderRange: [UInt32] {
        get throws { try properties.array(global(kAudioSliderControlPropertyRange), of: UInt32.self) }
    }

    open var volumeScalarValue: Float {
        get throws { try properties.get(global(kAudioLevelControlPropertyScalarValue), Float32(0)) }
    }

    open var volumeDecibelValue: Float {
        get throws { try properties.get(global(kAudioLevelControlPropertyDecibelValue), Float32(0)) }
    }

    open var volumeDecibelRange: AudioValueRange {
        get throws { try properties.get(global(kAudioLevelControlPropertyDecibelRange), AudioValueRange()) }
    }

    open var booleanValue: Bool {
        get throws { try properties.bool(global(kAudioBooleanControlPropertyValue)) }
    }

    open var selectedItems: [UInt32] {
        get throws { try properties.array(global(kAudioSelectorControlPropertyCurrentItem), of: UInt32.self) }
    }

    open var availableItems: [UInt32] {
        get throws { try properties.array(global(kAudioSelectorControlPropertyAvailableItems), of: UInt32.self) }
    }

    open var stereoPanValue: Float {
        get throws { try properties.get(global(kAudioStereoPanControlPropertyValue), Float32(0)) }
    }

    open var stereoPanChannels: [UInt32] {
        get throws { try properties.array(global(kAudioStereoPanControlPropertyPanningChannels), of: UInt32.self) }
    }

    open func setSliderValue(_ value: UInt32) throws {
        try properties.set(global(kAudioSliderControlPropertyValue), value)
    }

    open func setVolumeScalarValue(_ value: Float) throws {
        try properties.set(global(kAudioLevelControlPropertyScalarValue), Float32(value))
    }

    open func setVolumeDecibelValue(_ value: Float) throws {
        try properties.set(global(kAudioLevelControlPropertyDecibelValue), Float32(value))
    }

    open func setBooleanValue(_ value: Bool) throws {
        try properties.setBool(global(kAudioBooleanControlPropertyValue), value)
    }

    open func setSelectedItems(_ items: [UInt32]) throws {
        try properties.setArray(global(kAudioSelectorControlPropertyCurrentItem), items)
    }

    open func setStereoPanValue(_ value: Float) throws {
        try properties.set(global(kAudioStereoPanControlPropertyValue), Float32(value))
    }

    open func convertToDecibels(fromScalar scalar: Float) throws -> Float {
        try properties.get(global(kAudioLevelControlPropertyConvertScalarToDecibels), Float32(scalar))
    }

    open func convertToScalar(fromDecibels decibels: Float) throws -> Float {
        try properties.get(global(kAudioLevelControlPropertyConvertDecibelsToScalar), Float32(decibels))
    }

    open func selectorItemName(fromID ID: UInt32) throws -> String {
        try properties.string(global(kAudioSelectorControlPropertyItemName), qualifier: qualifier(ID))
    }

    open func selectorItemKind(fromID ID: UInt32) throws -> UInt32 {
        try properties.get(global(kAudioSelectorControlPropertyItemKind), qualifier: qualifier(ID), UInt32(0))
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareClock: AudioHardwareObject, @unchecked Sendable {
    /// A device's UID is a device property; a clock device's its own.
    open var uid: String {
        get throws {
            try properties.string(global(self is AudioHardwareDevice ? kAudioDevicePropertyDeviceUID : kAudioClockDevicePropertyDeviceUID))
        }
    }

    open var transportType: UInt32 {
        get throws { try properties.get(global(kAudioDevicePropertyTransportType), UInt32(0)) }
    }

    open var clockDomain: UInt32 {
        get throws { try properties.get(global(kAudioDevicePropertyClockDomain), UInt32(0)) }
    }

    open var isAlive: Bool {
        get throws { try properties.bool(global(kAudioDevicePropertyDeviceIsAlive)) }
    }

    open var isRunning: Bool {
        get throws { try properties.bool(global(kAudioDevicePropertyDeviceIsRunning)) }
    }

    open var inputLatency: Int {
        get throws { try properties.int(input(kAudioDevicePropertyLatency)) }
    }

    open var outputLatency: Int {
        get throws { try properties.int(output(kAudioDevicePropertyLatency)) }
    }

    open var controls: [AudioHardwareControl] {
        get throws { try properties.ids(global(kAudioObjectPropertyControlList)).map(AudioHardwareControl.init) }
    }

    open var nominalSampleRate: Double {
        get throws { try properties.get(global(kAudioDevicePropertyNominalSampleRate), Float64(0)) }
    }

    open var availableNominalSampleRates: [AudioValueRange] {
        get throws { try properties.array(global(kAudioDevicePropertyAvailableNominalSampleRates), of: AudioValueRange.self) }
    }

    open func setNominalSampleRate(_ sampleRate: Double) throws {
        try properties.set(global(kAudioDevicePropertyNominalSampleRate), Float64(sampleRate))
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareDevice: AudioHardwareClock, @unchecked Sendable {
    open var configurationApplication: String {
        get throws { try properties.string(global(kAudioDevicePropertyConfigurationApplication)) }
    }

    open var modelUID: String {
        get throws { try properties.string(global(kAudioDevicePropertyModelUID)) }
    }

    open var relatedDevices: [AudioHardwareDevice] {
        get throws { try properties.ids(global(kAudioDevicePropertyRelatedDevices)).map(makeDevice) }
    }

    open var canBeDefaultInputDevice: Bool {
        get throws { try properties.bool(input(kAudioDevicePropertyDeviceCanBeDefaultDevice)) }
    }

    open var canBeDefaultOutputDevice: Bool {
        get throws { try properties.bool(output(kAudioDevicePropertyDeviceCanBeDefaultDevice)) }
    }

    open var canBeDefaultSoundEffectsDevice: Bool {
        get throws { try properties.bool(output(kAudioDevicePropertyDeviceCanBeDefaultSystemDevice)) }
    }

    open var streams: [AudioHardwareStream] {
        get throws { try properties.ids(global(kAudioDevicePropertyStreams)).map(AudioHardwareStream.init) }
    }

    open var inputSafetyOffset: Int {
        get throws { try properties.int(input(kAudioDevicePropertySafetyOffset)) }
    }

    open var outputSafetyOffset: Int {
        get throws { try properties.int(output(kAudioDevicePropertySafetyOffset)) }
    }

    open var icon: URL? {
        get throws { try properties.object(global(kAudioDevicePropertyIcon)).map { $0 as! CFURL as URL } }
    }

    open var isHidden: Bool {
        get throws { try properties.bool(global(kAudioDevicePropertyIsHidden)) }
    }

    open var preferredInputChannelsForStereo: [UInt32] {
        get throws { try properties.array(input(kAudioDevicePropertyPreferredChannelsForStereo), of: UInt32.self) }
    }

    open var preferredOutputChannelsForStereo: [UInt32] {
        get throws { try properties.array(output(kAudioDevicePropertyPreferredChannelsForStereo), of: UInt32.self) }
    }

    open var isRunningInAProcess: Bool {
        get throws { try properties.bool(global(kAudioDevicePropertyDeviceIsRunningSomewhere)) }
    }

    open var hogModePID: pid_t {
        get throws { try properties.get(global(kAudioDevicePropertyHogMode), pid_t(-1)) }
    }

    open var bufferFrameSize: Int {
        get throws { try properties.int(global(kAudioDevicePropertyBufferFrameSize)) }
    }

    open var bufferFrameSizeRange: AudioValueRange {
        get throws { try properties.get(global(kAudioDevicePropertyBufferFrameSizeRange), AudioValueRange()) }
    }

    /// Whether the device implements variable buffer sizes; their largest
    /// is the property's value.
    open var usesVariableBufferFrameSizes: Bool {
        get throws {
            let address = global(kAudioDevicePropertyUsesVariableBufferFrameSizes)
            guard properties.has(address) else { return false }
            return try properties.get(address, UInt32(0)) != 0
        }
    }

    open var largestVariableBufferFrameSize: Int {
        get throws { try properties.int(global(kAudioDevicePropertyUsesVariableBufferFrameSizes)) }
    }

    open var ioCycleUsage: Float {
        get throws { try properties.get(global(kAudioDevicePropertyIOCycleUsage), Float32(0)) }
    }

    /// The buffers of the device's stream configuration in a scope.
    private func streamConfiguration(_ address: AudioObjectPropertyAddress) throws -> [AudioBuffer] {
        var data = try properties.data(address)
        return data.withUnsafeMutableBytes { bytes in
            guard bytes.count >= MemoryLayout<UInt32>.size else { return [] }
            let list = UnsafeMutableAudioBufferListPointer(bytes.baseAddress!.assumingMemoryBound(to: AudioBufferList.self))
            return Array(list)
        }
    }

    open var inputStreamConfiguration: [AudioBuffer] {
        get throws { try streamConfiguration(input(kAudioDevicePropertyStreamConfiguration)) }
    }

    open var outputStreamConfiguration: [AudioBuffer] {
        get throws { try streamConfiguration(output(kAudioDevicePropertyStreamConfiguration)) }
    }

    open var actualSampleRate: Double {
        get throws { try properties.get(global(kAudioDevicePropertyActualSampleRate), Float64(0)) }
    }

    /// The clock device the device runs from, by its UID; the device itself
    /// when it names none.
    open var clock: AudioHardwareClock {
        get throws {
            let uid = (try? properties.object(global(kAudioDevicePropertyClockDevice))) as? String ?? ""
            if !uid.isEmpty, let clock = try clockOrDevice(uid: uid) {
                return clock
            }
            return self
        }
    }

    open var workgroup: WorkGroup {
        get throws {
            guard let group = try properties.object(global(kAudioDevicePropertyIOThreadOSWorkgroup)) as? WorkGroup else {
                throw AudioHardwareError(OSStatus(kAudioHardwareUnspecifiedError))
            }
            return group
        }
    }

    open var isProcessInputMuted: Bool {
        get throws { try properties.bool(input(kAudioDevicePropertyProcessMute)) }
    }

    open var isProcessOutputMuted: Bool {
        get throws { try properties.bool(output(kAudioDevicePropertyProcessMute)) }
    }

    open var currentTime: AudioTimeStamp {
        get throws {
            var time = AudioTimeStamp()
            try check(AudioDeviceGetCurrentTime(id, &time))
            return time
        }
    }

    open func setPreferredInputChannelsForStereo(_ channels: [UInt32]) throws {
        try properties.setData(input(kAudioDevicePropertyPreferredChannelsForStereo), channels.withUnsafeBytes { Data($0) })
    }

    open func setPreferredOutputChannelsForStereo(_ channels: [UInt32]) throws {
        try properties.setData(output(kAudioDevicePropertyPreferredChannelsForStereo), channels.withUnsafeBytes { Data($0) })
    }

    open func setBufferFrameSize(_ size: Int) throws {
        try properties.set(global(kAudioDevicePropertyBufferFrameSize), UInt32(size))
    }

    open func setIOCycleUsage(_ usage: Float) throws {
        try properties.set(global(kAudioDevicePropertyIOCycleUsage), Float32(usage))
    }

    open func setClock(_ clock: AudioHardwareClock) throws {
        try properties.setObject(global(kAudioDevicePropertyClockDevice), try clock.uid as CFString)
    }

    open func setIsProcessInputMuted(_ muted: Bool) throws {
        try properties.setBool(input(kAudioDevicePropertyProcessMute), muted)
    }

    open func setIsProcessOutputMuted(_ muted: Bool) throws {
        try properties.setBool(output(kAudioDevicePropertyProcessMute), muted)
    }

    /// Takes hog mode when no process has it, else gives it up; returns the
    /// process that has it after (-1 for none).
    open func toggleHogMode() throws -> pid_t {
        let address = global(kAudioDevicePropertyHogMode)
        let current = try properties.get(address, pid_t(-1))
        try properties.set(address, current == getpid() ? pid_t(-1) : getpid())
        return try properties.get(address, pid_t(-1))
    }

    open func translateTime(_ timestamp: AudioTimeStamp) throws -> AudioTimeStamp {
        var time = timestamp
        var translated = AudioTimeStamp()
        translated.mFlags = [.sampleTimeValid, .hostTimeValid, .rateScalarValid]
        try check(AudioDeviceTranslateTime(id, &time, &translated))
        return translated
    }

    open func nearestStartTime(atTime timestamp: AudioTimeStamp, withFlags flags: UInt32 = 0) throws -> AudioTimeStamp {
        var time = timestamp
        try check(AudioDeviceGetNearestStartTime(id, &time, flags))
        return time
    }

    open func start(IOProcID: AudioDeviceIOProcID? = nil) throws {
        try check(AudioDeviceStart(id, IOProcID))
    }

    open func start(at time: AudioTimeStamp, flags: UInt32 = 0, IOProcID: AudioDeviceIOProcID? = nil) throws -> AudioTimeStamp? {
        var start = time
        try check(AudioDeviceStartAtTime(id, IOProcID, &start, flags))
        return start
    }

    open func stop(IOProcID: AudioDeviceIOProcID? = nil) throws {
        try check(AudioDeviceStop(id, IOProcID))
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwarePlugin: AudioHardwareObject, @unchecked Sendable {
    open var bundleID: String {
        get throws { try properties.string(global(kAudioPlugInPropertyBundleID)) }
    }

    open var devices: [AudioHardwareDevice] {
        get throws { try properties.ids(global(kAudioPlugInPropertyDeviceList)).map(makeDevice) }
    }

    open var boxes: [AudioHardwareBox] {
        get throws { try properties.ids(global(kAudioPlugInPropertyBoxList)).map(AudioHardwareBox.init) }
    }

    open var clocks: [AudioHardwareClock] {
        get throws { try properties.ids(global(kAudioPlugInPropertyClockDeviceList)).map(makeClock) }
    }

    open func device(forUID UID: String) throws -> AudioHardwareDevice? {
        try properties.translate(global(kAudioPlugInPropertyTranslateUIDToDevice), UID).map(makeDevice)
    }

    open func box(forUID UID: String) throws -> AudioHardwareBox? {
        try properties.translate(global(kAudioPlugInPropertyTranslateUIDToBox), UID).map(AudioHardwareBox.init)
    }

    open func clock(forUID UID: String) throws -> AudioHardwareClock? {
        try properties.translate(global(kAudioPlugInPropertyTranslateUIDToClockDevice), UID).map(makeClock)
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareAggregateDevice: AudioHardwareDevice, @unchecked Sendable {
    /// The UIDs a property lists, as a CFArray of CFStrings.
    private func uids(_ selector: AudioObjectPropertySelector) throws -> [String] {
        (try properties.object(global(selector)) as? [String]) ?? []
    }

    open var subdevices: [AudioHardwareClock] {
        get throws { try uids(kAudioAggregateDevicePropertyFullSubDeviceList).compactMap { try clockOrDevice(uid: $0) } }
    }

    open var activeSubdevices: [AudioHardwareClock] {
        get throws { try properties.ids(global(kAudioAggregateDevicePropertyActiveSubDeviceList)).map(makeClock) }
    }

    open var subtaps: [AudioHardwareTap] {
        get throws { try uids(kAudioAggregateDevicePropertyTapList).compactMap { try AudioHardwareSystem.shared.tap(forUID: $0) } }
    }

    open var activeSubtaps: [AudioHardwareTap] {
        get throws { try properties.ids(global(kAudioAggregateDevicePropertySubTapList)).map(AudioHardwareTap.init) }
    }

    /// The clock device the aggregate runs from, else its main subdevice.
    open var clockSource: AudioHardwareObject? {
        get throws {
            for selector in [kAudioAggregateDevicePropertyClockDevice, kAudioAggregateDevicePropertyMainSubDevice] {
                if let uid = (try? properties.object(global(selector))) as? String, !uid.isEmpty,
                   let source = try clockOrDevice(uid: uid) {
                    return source
                }
            }
            return nil
        }
    }

    open var composition: [String: Any] {
        get throws { (try properties.object(global(kAudioAggregateDevicePropertyComposition)) as? [String: Any]) ?? [:] }
    }

    open func setSubdevices(_ devices: [AudioHardwareClock]) throws {
        try properties.setObject(global(kAudioAggregateDevicePropertyFullSubDeviceList), try devices.map { try $0.uid } as CFArray)
    }

    open func setSubtaps(_ taps: [AudioHardwareTap]) throws {
        try properties.setObject(global(kAudioAggregateDevicePropertyTapList), try taps.map { try $0.uid } as CFArray)
    }

    /// A clock device becomes the aggregate's clock; a device its main
    /// subdevice.
    open func setClockSource(_ object: AudioHardwareObject) throws {
        if let device = object as? AudioHardwareDevice {
            try properties.setObject(global(kAudioAggregateDevicePropertyMainSubDevice), try device.uid as CFString)
        } else if let clock = object as? AudioHardwareClock {
            try properties.setObject(global(kAudioAggregateDevicePropertyClockDevice), try clock.uid as CFString)
        } else {
            throw AudioHardwareError(OSStatus(kAudioHardwareIllegalOperationError))
        }
    }

    open func setComposition(_ composition: [String: Any]) throws {
        try properties.setObject(global(kAudioAggregateDevicePropertyComposition), composition as CFDictionary)
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

@_inheritsConvenienceInitializers
@available(macOS 15.0, *)
open class AudioHardwareTap: AudioHardwareObject, @unchecked Sendable {
    open var uid: String {
        get throws { try properties.string(global(kAudioTapPropertyUID)) }
    }

    open var description: CATapDescription {
        get throws {
            guard let description = try properties.object(global(kAudioTapPropertyDescription)) as? CATapDescription else {
                throw AudioHardwareError(OSStatus(kAudioHardwareUnspecifiedError))
            }
            return description
        }
    }

    open var format: AudioStreamBasicDescription {
        get throws { try properties.get(global(kAudioTapPropertyFormat), AudioStreamBasicDescription()) }
    }

    open func setDescription(_ description: CATapDescription) throws {
        try properties.setObject(global(kAudioTapPropertyDescription), description)
    }

    public override init(id: AudioObjectID) {
        super.init(id: id)
    }
}

extension AudioHardwareDirection: Equatable {}
extension AudioHardwareDirection: Hashable {}
extension AudioHardwareDirection: RawRepresentable {}

#endif
