import PerryObjCInterop

/// CoreBluetooth's string constants, with Darwin's values.
@ObjCConstants
enum Constants {
    // Advertisement data.
    static let CBAdvertisementDataLocalNameKey = "kCBAdvDataLocalName"
    static let CBAdvertisementDataManufacturerDataKey = "kCBAdvDataManufacturerData"
    static let CBAdvertisementDataServiceDataKey = "kCBAdvDataServiceData"
    static let CBAdvertisementDataServiceUUIDsKey = "kCBAdvDataServiceUUIDs"
    static let CBAdvertisementDataOverflowServiceUUIDsKey = "kCBAdvDataHashedServiceUUIDs"
    static let CBAdvertisementDataTxPowerLevelKey = "kCBAdvDataTxPowerLevel"
    static let CBAdvertisementDataIsConnectable = "kCBAdvDataIsConnectable"
    static let CBAdvertisementDataSolicitedServiceUUIDsKey = "kCBAdvDataSolicitedServiceUUIDs"

    // Central manager options.
    static let CBCentralManagerOptionShowPowerAlertKey = "kCBInitOptionShowPowerAlert"
    static let CBCentralManagerOptionRestoreIdentifierKey = "kCBInitOptionRestoreIdentifier"
    static let CBCentralManagerScanOptionAllowDuplicatesKey = "kCBScanOptionAllowDuplicates"
    static let CBCentralManagerScanOptionSolicitedServiceUUIDsKey = "kCBScanOptionSolicitedServiceUUIDs"
    static let CBCentralManagerRestoredStatePeripheralsKey = "kCBRestoredPeripherals"
    static let CBCentralManagerRestoredStateScanServicesKey = "kCBRestoredScanServices"
    static let CBCentralManagerRestoredStateScanOptionsKey = "kCBRestoredScanOptions"
    static let CBConnectPeripheralOptionNotifyOnConnectionKey = "kCBConnectOptionNotifyOnConnection"
    static let CBConnectPeripheralOptionNotifyOnDisconnectionKey = "kCBConnectOptionNotifyOnDisconnection"
    static let CBConnectPeripheralOptionNotifyOnNotificationKey = "kCBConnectOptionNotifyOnNotification"
    static let CBConnectPeripheralOptionStartDelayKey = "kCBConnectOptionStartDelay"
    static let CBConnectPeripheralOptionEnableTransportBridgingKey = "kCBConnectOptionEnableTransportBridging"
    static let CBConnectPeripheralOptionRequiresANCS = "kCBConnectOptionRequiresANCS"
    static let CBConnectPeripheralOptionEnableAutoReconnect = "kCBConnectOptionEnableAutoReconnect"

    // Peripheral manager options.
    static let CBPeripheralManagerOptionShowPowerAlertKey = "kCBInitOptionShowPowerAlert"
    static let CBPeripheralManagerOptionRestoreIdentifierKey = "kCBInitOptionRestoreIdentifier"
    static let CBPeripheralManagerRestoredStateServicesKey = "kCBRestoredServices"
    static let CBPeripheralManagerRestoredStateAdvertisementDataKey = "kCBRestoredAdvertisement"

    // Errors.
    static let CBErrorDomain = "CBErrorDomain"
    static let CBATTErrorDomain = "CBATTErrorDomain"

    // Descriptor UUIDs.
    static let CBUUIDCharacteristicExtendedPropertiesString = "2900"
    static let CBUUIDCharacteristicUserDescriptionString = "2901"
    static let CBUUIDClientCharacteristicConfigurationString = "2902"
    static let CBUUIDServerCharacteristicConfigurationString = "2903"
    static let CBUUIDCharacteristicFormatString = "2904"
    static let CBUUIDCharacteristicAggregateFormatString = "2905"
    static let CBUUIDCharacteristicValidRangeString = "2906"
    static let CBUUIDL2CAPPSMCharacteristicString = "ABDD3056-28FA-441D-A470-55A75A52553A"
}
