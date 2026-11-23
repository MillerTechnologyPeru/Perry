import Foundation

// The intents, responses and reservations whose Objective-C initializers
// and properties take NSNumbers: Swift optionals of the numbers' types.
// Nearly all of them are for iOS and watchOS only, unavailable on macOS as
// in the SDK; they're here for the symbols of the zippered library.

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaSearch {
    @nonobjc public convenience init(mediaType: INMediaItemType = .unknown, sortOrder: INMediaSortOrder = .unknown, mediaName: String? = nil, artistName: String? = nil, albumName: String? = nil, genreNames: [String]? = nil, moodNames: [String]? = nil, releaseDate: INDateComponentsRange? = nil, reference: INMediaReference = .unknown, mediaIdentifier: String? = nil) {
        self.init(__mediaType: mediaType, sortOrder: sortOrder, mediaName: mediaName, artistName: artistName, albumName: albumName, genreNames: genreNames, moodNames: moodNames, releaseDate: releaseDate, reference: reference, mediaIdentifier: mediaIdentifier)
    }
}

@available(macOS 10.15, iOS 10.3, watchOS 3.2, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSetCarLockStatusIntent {
    @nonobjc public convenience init(locked: Bool?, carName: INSpeakableString?) {
        self.init(__locked: locked.number, carName: carName)
    }

    @nonobjc public final var locked: Bool? { __locked.bool }
}

@available(macOS 10.15, iOS 10.0, watchOS 3.2, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INRequestRideIntent {
    @nonobjc public convenience init(pickupLocation: CLPlacemark? = nil, dropOffLocation: CLPlacemark? = nil, rideOptionName: INSpeakableString? = nil, partySize: Int? = nil, paymentMethod: INPaymentMethod? = nil, scheduledPickupTime: INDateComponentsRange? = nil) {
        self.init(__pickupLocation: pickupLocation, dropOffLocation: dropOffLocation, rideOptionName: rideOptionName, partySize: partySize.number, paymentMethod: paymentMethod, scheduledPickupTime: scheduledPickupTime)
    }

    @nonobjc public final var partySize: Int? { __partySize.int }
}

@available(macOS 10.15, iOS 10.0, watchOS 3.2, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INRideOption {
    @available(iOS 10.0, watchOS 3.2, *)
    @available(swift, obsoleted: 4)
    @nonobjc public var usesMeteredFare: NSNumber? {
        get { __usesMeteredFare }
        set(newUsesMeteredFare) { __usesMeteredFare = newUsesMeteredFare }
    }

    @available(swift 4.0)
    @available(iOS 10.0, watchOS 3.2, *)
    @nonobjc public var usesMeteredFare: Bool? {
        get { __usesMeteredFare.bool }
        set(newUsesMeteredFare) { __usesMeteredFare = newUsesMeteredFare.number }
    }
}

@available(macOS 10.15, iOS 12.0, watchOS 5.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INPlayMediaIntent {
    @available(iOS, introduced: 12.0, obsoleted: 13.0)
    @available(watchOS, introduced: 5.0, obsoleted: 6.0)
    @available(tvOS, unavailable)
    @nonobjc public convenience init(mediaItems: [INMediaItem]? = nil, mediaContainer: INMediaItem? = nil, playShuffled: Bool? = nil, playbackRepeatMode: INPlaybackRepeatMode = .unknown, resumePlayback: Bool? = nil) {
        self.init(__mediaItems: mediaItems, mediaContainer: mediaContainer, playShuffled: playShuffled.number, playbackRepeatMode: playbackRepeatMode, resumePlayback: resumePlayback.number, playbackQueueLocation: .unknown, playbackSpeed: nil, mediaSearch: nil)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
    @nonobjc public convenience init(mediaItems: [INMediaItem]? = nil, mediaContainer: INMediaItem? = nil, playShuffled: Bool? = nil, playbackRepeatMode: INPlaybackRepeatMode = .unknown, resumePlayback: Bool? = nil, playbackQueueLocation: INPlaybackQueueLocation = .unknown, playbackSpeed: Double? = nil, mediaSearch: INMediaSearch? = nil) {
        self.init(__mediaItems: mediaItems, mediaContainer: mediaContainer, playShuffled: playShuffled.number, playbackRepeatMode: playbackRepeatMode, resumePlayback: resumePlayback.number, playbackQueueLocation: playbackQueueLocation, playbackSpeed: playbackSpeed.number, mediaSearch: mediaSearch)
    }

    @nonobjc public final var playShuffled: Bool? { __playShuffled.bool }
    @nonobjc public final var resumePlayback: Bool? { __resumePlayback.bool }

    @available(iOS 13.0, watchOS 6.0, *)
    @nonobjc public final var playbackSpeed: Double? { __playbackSpeed.double }
}

@available(macOS, unavailable)
@available(tvOS, unavailable)
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "INSearchCallHistoryIntent is deprecated. There is no replacement.")
@available(watchOS, introduced: 3.2, deprecated: 8.0, message: "INSearchCallHistoryIntent is deprecated. There is no replacement.")
extension INSearchCallHistoryIntent {
    @nonobjc public convenience init(dateCreated: INDateComponentsRange? = nil, recipient: INPerson? = nil, callCapabilities: INCallCapabilityOptions, callTypes: INCallRecordTypeOptions, unseen: Bool? = nil) {
        self.init(__dateCreated: dateCreated, recipient: recipient, callCapabilities: callCapabilities, callTypes: callTypes, unseen: unseen.number)
    }

    @nonobjc public final var unseen: Bool? { __unseen.bool }
}

@available(iOS, introduced: 10.0, deprecated: 15.0, message: "INSetDefrosterSettingsInCarIntent is deprecated. There is no replacement.")
@available(watchOS, introduced: 3.2, deprecated: 8.0, message: "INSetDefrosterSettingsInCarIntent is deprecated. There is no replacement.")
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSetDefrosterSettingsInCarIntent {
    @nonobjc public convenience init(enable: Bool? = nil, defroster: INCarDefroster = .unknown, carName: INSpeakableString? = nil) {
        self.init(__enable: enable.number, defroster: defroster, carName: carName)
    }

    @available(iOS, obsoleted: 12.0)
    @available(watchOS, unavailable)
    @nonobjc public convenience init(enable: Bool? = nil, defroster: INCarDefroster = .unknown) {
        self.init(__enable: enable.number, defroster: defroster, carName: nil)
    }

    @nonobjc public final var enable: Bool? { __enable.bool }
}

@available(iOS, introduced: 10.0, deprecated: 15.0, message: "INSetClimateSettingsInCarIntent is deprecated. There is no replacement.")
@available(watchOS, introduced: 3.2, deprecated: 8.0, message: "INSetClimateSettingsInCarIntent is deprecated. There is no replacement.")
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSetClimateSettingsInCarIntent {
    @nonobjc public convenience init(enableFan: Bool? = nil, enableAirConditioner: Bool? = nil, enableClimateControl: Bool? = nil, enableAutoMode: Bool? = nil, airCirculationMode: INCarAirCirculationMode = .unknown, fanSpeedIndex: Int? = nil, fanSpeedPercentage: Double? = nil, relativeFanSpeedSetting: INRelativeSetting = .unknown, temperature: Measurement<UnitTemperature>? = nil, relativeTemperatureSetting: INRelativeSetting = .unknown, climateZone: INCarSeat = .unknown, carName: INSpeakableString? = nil) {
        self.init(__enableFan: enableFan.number, enableAirConditioner: enableAirConditioner.number, enableClimateControl: enableClimateControl.number, enableAutoMode: enableAutoMode.number, airCirculationMode: airCirculationMode, fanSpeedIndex: fanSpeedIndex.number, fanSpeedPercentage: fanSpeedPercentage.number, relativeFanSpeedSetting: relativeFanSpeedSetting, temperature: temperature, relativeTemperatureSetting: relativeTemperatureSetting, climateZone: climateZone, carName: carName)
    }

    @available(iOS, obsoleted: 12.0)
    @available(watchOS, unavailable)
    @nonobjc public convenience init(enableFan: Bool? = nil, enableAirConditioner: Bool? = nil, enableClimateControl: Bool? = nil, enableAutoMode: Bool? = nil, airCirculationMode: INCarAirCirculationMode = .unknown, fanSpeedIndex: Int? = nil, fanSpeedPercentage: Double? = nil, relativeFanSpeedSetting: INRelativeSetting = .unknown, temperature: Measurement<UnitTemperature>? = nil, relativeTemperatureSetting: INRelativeSetting = .unknown, climateZone: INCarSeat = .unknown) {
        self.init(enableFan: enableFan, enableAirConditioner: enableAirConditioner, enableClimateControl: enableClimateControl, enableAutoMode: enableAutoMode, airCirculationMode: airCirculationMode, fanSpeedIndex: fanSpeedIndex, fanSpeedPercentage: fanSpeedPercentage, relativeFanSpeedSetting: relativeFanSpeedSetting, temperature: temperature, relativeTemperatureSetting: relativeTemperatureSetting, climateZone: climateZone, carName: nil)
    }

    @nonobjc public final var enableFan: Bool? { __enableFan.bool }
    @nonobjc public final var enableAirConditioner: Bool? { __enableAirConditioner.bool }
    @nonobjc public final var enableClimateControl: Bool? { __enableClimateControl.bool }
    @nonobjc public final var enableAutoMode: Bool? { __enableAutoMode.bool }
    @nonobjc public final var fanSpeedIndex: Int? { __fanSpeedIndex.int }
    @nonobjc public final var fanSpeedPercentage: Double? { __fanSpeedPercentage.double }
}

// The profile intent's older initializers named the profile's label and
// whether it's the default with a number; all of them go to the
// designated initializer, the label as the name.
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "INSetProfileInCarIntent is deprecated. There is no replacement.")
@available(watchOS, introduced: 3.2, deprecated: 8.0, message: "INSetProfileInCarIntent is deprecated. There is no replacement.")
@available(macOS, unavailable)
@available(tvOS, unavailable)
@nonobjc extension INSetProfileInCarIntent {
    public convenience init(profileNumber: Int? = nil, profileName: String? = nil, isDefaultProfile: Bool? = nil, carName: INSpeakableString? = nil) {
        self.init(__profileNumber: profileNumber.number, profileName: profileName, defaultProfile: isDefaultProfile.number, carName: carName)
    }

    @available(iOS, introduced: 11.0, obsoleted: 12.0)
    @available(watchOS, unavailable)
    public convenience init(profileNumber: Int? = nil, profileName: String? = nil, isDefaultProfile: Bool? = nil) {
        self.init(profileNumber: profileNumber, profileName: profileName, isDefaultProfile: isDefaultProfile, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(defaultProfile: Int?) {
        self.init(__profileNumber: nil, profileName: nil, defaultProfile: defaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileLabel: String?) {
        self.init(__profileNumber: nil, profileName: profileLabel, defaultProfile: nil, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileLabel: String?, defaultProfile: Int?) {
        self.init(__profileNumber: nil, profileName: profileLabel, defaultProfile: defaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileLabel: String?, isDefaultProfile: Bool?) {
        self.init(__profileNumber: nil, profileName: profileLabel, defaultProfile: isDefaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileName: String?, defaultProfile: Int?) {
        self.init(__profileNumber: nil, profileName: profileName, defaultProfile: defaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileNumber: Int?, defaultProfile: Int?) {
        self.init(__profileNumber: profileNumber.number, profileName: nil, defaultProfile: defaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileNumber: Int?, profileLabel: String?) {
        self.init(__profileNumber: profileNumber.number, profileName: profileLabel, defaultProfile: nil, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileNumber: Int?, profileLabel: String?, defaultProfile: Int?) {
        self.init(__profileNumber: profileNumber.number, profileName: profileLabel, defaultProfile: defaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileNumber: Int?, profileLabel: String?, isDefaultProfile: Bool?) {
        self.init(__profileNumber: profileNumber.number, profileName: profileLabel, defaultProfile: isDefaultProfile.number, carName: nil)
    }

    @available(iOS, deprecated: 11.0, renamed: "init(profileNumber:profileName:isDefaultProfile:)")
    @available(watchOS, unavailable)
    public convenience init(profileNumber: Int?, profileName: String?, defaultProfile: Int?) {
        self.init(__profileNumber: profileNumber.number, profileName: profileName, defaultProfile: defaultProfile.number, carName: nil)
    }

    public var isDefaultProfile: Bool? { __defaultProfile.bool }

    @available(swift, deprecated: 3.2, obsoleted: 4.0, message: "Please use isDefaultProfile instead")
    public var defaultProfile: Int? { __defaultProfile.int }

    public final var profileNumber: Int? { __profileNumber.int }
}

@available(iOS, introduced: 10.0, deprecated: 15.0, message: "INSetSeatSettingsInCarIntent is deprecated. There is no replacement.")
@available(watchOS, introduced: 3.2, deprecated: 8.0, message: "INSetSeatSettingsInCarIntent is deprecated. There is no replacement.")
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSetSeatSettingsInCarIntent {
    @nonobjc public convenience init(enableHeating: Bool? = nil, enableCooling: Bool? = nil, enableMassage: Bool? = nil, seat: INCarSeat = .unknown, level: Int? = nil, relativeLevel: INRelativeSetting = .unknown, carName: INSpeakableString? = nil) {
        self.init(__enableHeating: enableHeating.number, enableCooling: enableCooling.number, enableMassage: enableMassage.number, seat: seat, level: level.number, relativeLevel: relativeLevel, carName: carName)
    }

    @available(iOS, obsoleted: 12.0)
    @available(watchOS, unavailable)
    @nonobjc public convenience init(enableHeating: Bool? = nil, enableCooling: Bool? = nil, enableMassage: Bool? = nil, seat: INCarSeat = .unknown, level: Int? = nil, relativeLevel: INRelativeSetting = .unknown) {
        self.init(enableHeating: enableHeating, enableCooling: enableCooling, enableMassage: enableMassage, seat: seat, level: level, relativeLevel: relativeLevel, carName: nil)
    }

    @nonobjc public final var enableHeating: Bool? { __enableHeating.bool }
    @nonobjc public final var enableCooling: Bool? { __enableCooling.bool }
    @nonobjc public final var enableMassage: Bool? { __enableMassage.bool }
    @nonobjc public final var level: Int? { __level.int }
}

@available(macOS 10.15, iOS 11.0, watchOS 4.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INCallRecord {
    @available(iOS 13.0, watchOS 6.0, *)
    @nonobjc public convenience init(identifier: String, dateCreated: Date? = nil, caller: INPerson? = nil, callRecordType: INCallRecordType = .unknown, callCapability: INCallCapability = .unknown, callDuration: Double? = nil, unseen: Bool? = nil, numberOfCalls: Int? = nil) {
        self.init(__identifier: identifier, dateCreated: dateCreated, callRecordType: callRecordType, callCapability: callCapability, callDuration: callDuration.number, unseen: unseen.number, participants: caller.map { [$0] }, numberOfCalls: numberOfCalls.number, isCallerIdBlocked: nil)
    }

    @available(iOS, obsoleted: 13.0)
    @available(watchOS, obsoleted: 6.0)
    @nonobjc public convenience init(identifier: String, dateCreated: Date? = nil, caller: INPerson? = nil, callRecordType: INCallRecordType, callCapability: INCallCapability, callDuration: Double? = nil, unseen: Bool? = nil) {
        self.init(__identifier: identifier, dateCreated: dateCreated, callRecordType: callRecordType, callCapability: callCapability, callDuration: callDuration.number, unseen: unseen.number, participants: caller.map { [$0] }, numberOfCalls: nil, isCallerIdBlocked: nil)
    }

    @nonobjc public final var callDuration: Double? { __callDuration.double }
    @nonobjc public final var unseen: Bool? { __unseen.bool }

    @available(iOS 13.0, watchOS 6.0, *)
    @nonobjc public final var numberOfCalls: Int? { __numberOfCalls.int }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaUserContext {
    @available(iOS 13.0, watchOS 6.0, tvOS 14.0, *)
    @nonobjc public final var numberOfLibraryItems: Int? {
        get { __numberOfLibraryItems.int }
        set { __numberOfLibraryItems = newValue.number }
    }
}

@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INDeleteTasksIntent {
    @nonobjc public convenience init(taskList: INTaskList? = nil, tasks: [INTask]? = nil, all: Bool? = nil) {
        self.init(__taskList: taskList, tasks: tasks, all: all.number)
    }

    @nonobjc public final var all: Bool? { __all.bool }
}

@available(macOS 10.15, iOS 10.3, watchOS 3.2, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INGetCarPowerLevelStatusIntentResponse {
    @nonobjc public final var fuelPercentRemaining: Float? {
        get { __fuelPercentRemaining.float }
        set(newPercent) { __fuelPercentRemaining = newPercent.number }
    }

    @nonobjc public final var chargePercentRemaining: Float? {
        get { __chargePercentRemaining.float }
        set(newPercent) { __chargePercentRemaining = newPercent.number }
    }

    @available(iOS 12.0, watchOS 5.0, *)
    @nonobjc public final var charging: Bool? {
        get { __charging.bool }
        set(newCharging) { __charging = newCharging.number }
    }

    @available(iOS 12.0, watchOS 5.0, *)
    @nonobjc public final var minutesToFull: Int? {
        get { __minutesToFull.int }
        set(newMinutesToFull) { __minutesToFull = newMinutesToFull.number }
    }
}

@available(macOS 10.15, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSearchForPhotosIntentResponse {
    @nonobjc public final var searchResultsCount: Int? {
        get { __searchResultsCount.int }
        set { __searchResultsCount = newValue.number }
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSnoozeTasksIntent {
    @nonobjc public convenience init(tasks: [INTask]? = nil, nextTriggerTime: INDateComponentsRange? = nil, all: Bool? = nil) {
        self.init(__tasks: tasks, nextTriggerTime: nextTriggerTime, all: all.number)
    }

    @nonobjc public final var all: Bool? { __all.bool }
}

@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSaveProfileInCarIntent {
    @nonobjc public convenience init(profileNumber: Int? = nil, profileLabel: String? = nil) {
        self.init(__profileNumber: profileNumber.number, profileName: profileLabel)
    }

    @nonobjc public final var profileNumber: Int? { __profileNumber.int }
}

@available(macOS 10.15, iOS 10.0, watchOS 3.2, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INStartWorkoutIntent {
    @nonobjc public convenience init(workoutName: INSpeakableString? = nil, goalValue: Double? = nil, workoutGoalUnitType: INWorkoutGoalUnitType = .unknown, workoutLocationType: INWorkoutLocationType = .unknown, isOpenEnded: Bool? = nil) {
        self.init(__workoutName: workoutName, goalValue: goalValue.number, workoutGoalUnitType: workoutGoalUnitType, workoutLocationType: workoutLocationType, isOpenEnded: isOpenEnded.number)
    }

    @nonobjc public final var goalValue: Double? { __goalValue.double }
    @nonobjc public final var isOpenEnded: Bool? { __isOpenEnded.bool }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INRestaurantReservation {
    @nonobjc public convenience init(itemReference: INSpeakableString, reservationNumber: String? = nil, bookingTime: Date? = nil, reservationStatus: INReservationStatus = .unknown, reservationHolderName: String? = nil, actions: [INReservationAction]? = nil, reservationDuration: INDateComponentsRange, partySize: Int? = nil, restaurantLocation: CLPlacemark) {
        self.init(itemReference: itemReference, reservationNumber: reservationNumber, bookingTime: bookingTime, reservationStatus: reservationStatus, reservationHolderName: reservationHolderName, actions: actions, url: nil, reservationDuration: reservationDuration, partySize: partySize, restaurantLocation: restaurantLocation)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, *)
    @nonobjc public convenience init(itemReference: INSpeakableString, reservationNumber: String? = nil, bookingTime: Date? = nil, reservationStatus: INReservationStatus = .unknown, reservationHolderName: String? = nil, actions: [INReservationAction]? = nil, url: URL? = nil, reservationDuration: INDateComponentsRange, partySize: Int? = nil, restaurantLocation: CLPlacemark) {
        self.init(__itemReference: itemReference, reservationNumber: reservationNumber, bookingTime: bookingTime, reservationStatus: reservationStatus, reservationHolderName: reservationHolderName, actions: actions, url: url, reservationDuration: reservationDuration, partySize: partySize.number, restaurantLocation: restaurantLocation)
    }

    @nonobjc public final var partySize: Int? { __partySize.int }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INLodgingReservation {
    @nonobjc public convenience init(itemReference: INSpeakableString, reservationNumber: String? = nil, bookingTime: Date? = nil, reservationStatus: INReservationStatus = .unknown, reservationHolderName: String? = nil, actions: [INReservationAction]? = nil, lodgingBusinessLocation: CLPlacemark, reservationDuration: INDateComponentsRange, numberOfAdults: Int? = nil, numberOfChildren: Int? = nil) {
        self.init(itemReference: itemReference, reservationNumber: reservationNumber, bookingTime: bookingTime, reservationStatus: reservationStatus, reservationHolderName: reservationHolderName, actions: actions, url: nil, lodgingBusinessLocation: lodgingBusinessLocation, reservationDuration: reservationDuration, numberOfAdults: numberOfAdults, numberOfChildren: numberOfChildren)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, *)
    @nonobjc public convenience init(itemReference: INSpeakableString, reservationNumber: String? = nil, bookingTime: Date? = nil, reservationStatus: INReservationStatus = .unknown, reservationHolderName: String? = nil, actions: [INReservationAction]? = nil, url: URL? = nil, lodgingBusinessLocation: CLPlacemark, reservationDuration: INDateComponentsRange, numberOfAdults: Int? = nil, numberOfChildren: Int? = nil) {
        self.init(__itemReference: itemReference, reservationNumber: reservationNumber, bookingTime: bookingTime, reservationStatus: reservationStatus, reservationHolderName: reservationHolderName, actions: actions, url: url, lodgingBusinessLocation: lodgingBusinessLocation, reservationDuration: reservationDuration, numberOfAdults: numberOfAdults.number, numberOfChildren: numberOfChildren.number)
    }

    @nonobjc public final var numberOfAdults: Int? { __numberOfAdults.int }
    @nonobjc public final var numberOfChildren: Int? { __numberOfChildren.int }
}

@available(macOS 10.15, iOS 10.3, watchOS 3.2, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INGetCarLockStatusIntentResponse {
    @nonobjc public final var locked: Bool? {
        get { __locked.bool }
        set(newLocked) { __locked = newLocked.number }
    }
}

@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INSetRadioStationIntent {
    @nonobjc public convenience init(radioType: INRadioType = .unknown, frequency: Double? = nil, stationName: String? = nil, channel: String? = nil, presetNumber: Int? = nil) {
        self.init(__radioType: radioType, frequency: frequency.number, stationName: stationName, channel: channel, presetNumber: presetNumber.number)
    }

    @nonobjc public final var frequency: Double? { __frequency.double }
    @nonobjc public final var presetNumber: Int? { __presetNumber.int }
}

@available(macOS 10.15, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INStartPhotoPlaybackIntentResponse {
    @nonobjc public final var searchResultsCount: Int? {
        get { __searchResultsCount.int }
        set { __searchResultsCount = newValue.number }
    }
}
