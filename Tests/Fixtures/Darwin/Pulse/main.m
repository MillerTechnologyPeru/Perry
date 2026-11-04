// A Bluetooth LE central for a heart rate monitor: scans for the Heart Rate
// service, connects, discovers its GATT database, reads the body sensor
// location, writes the control point, takes three measurements as
// notifications, stops them and disconnects; a monitor without the location
// or control point skips them. Each step waits for the one before, so the
// output is the same each run. Perry's tests run it against
// a fake BlueZ on a private D-Bus (Tests/Fixtures/bluez/fake-bluez.py).
#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>

static NSString *hex(NSData *data) {
    NSMutableString *string = [NSMutableString string];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) [string appendFormat:@"%02x", bytes[i]];
    return string;
}

@interface Central : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic) CBCentralManager *manager;
@property (nonatomic) CBPeripheral *peripheral;
@property (nonatomic) CBCharacteristic *measurement, *location, *controlPoint;
@property (nonatomic) int measurements;
@end

@implementation Central

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    printf("state %ld\n", (long)central.state);
    if (central.state != CBManagerStatePoweredOn) exit(1);
    [central scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:@"180D"]] options:nil];
    printf("scanning %s\n", central.isScanning ? "YES" : "NO");
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData RSSI:(NSNumber *)RSSI {
    printf("discovered %s %s RSSI %d\n", peripheral.name.UTF8String, peripheral.identifier.UUIDString.UTF8String, RSSI.intValue);
    printf("  name %s\n", [advertisementData[CBAdvertisementDataLocalNameKey] UTF8String]);
    printf("  manufacturer %s\n", hex(advertisementData[CBAdvertisementDataManufacturerDataKey]).UTF8String);
    for (CBUUID *uuid in advertisementData[CBAdvertisementDataServiceUUIDsKey]) printf("  service %s\n", uuid.UUIDString.UTF8String);
    printf("  connectable %d\n", [advertisementData[CBAdvertisementDataIsConnectable] intValue]);
    [central stopScan];
    printf("scanning %s\n", central.isScanning ? "YES" : "NO");
    NSArray *retrieved = [central retrievePeripheralsWithIdentifiers:@[peripheral.identifier]];
    printf("retrieved the same peripheral %s\n", retrieved.firstObject == peripheral ? "YES" : "NO");
    self.peripheral = peripheral;
    [central connectPeripheral:peripheral options:nil];
    printf("peripheral state %ld\n", (long)peripheral.state);
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    printf("connected, peripheral state %ld\n", (long)peripheral.state);
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    printf("failed to connect: %s\n", error.description.UTF8String);
    exit(1);
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    for (CBService *service in peripheral.services) {
        printf("service %s primary %s\n", service.UUID.UUIDString.UTF8String, service.isPrimary ? "YES" : "NO");
        if ([service.UUID isEqual:[CBUUID UUIDWithString:@"0000180d-0000-1000-8000-00805f9b34fb"]])
            [peripheral discoverCharacteristics:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    for (CBCharacteristic *characteristic in service.characteristics) {
        printf("characteristic %s properties 0x%02lx\n", characteristic.UUID.UUIDString.UTF8String, (unsigned long)characteristic.properties);
        NSString *uuid = characteristic.UUID.UUIDString;
        if ([uuid isEqualToString:@"2A37"]) self.measurement = characteristic;
        if ([uuid isEqualToString:@"2A38"]) self.location = characteristic;
        if ([uuid isEqualToString:@"2A39"]) self.controlPoint = characteristic;
    }
    if (self.location) [peripheral readValueForCharacteristic:self.location];
    else [self subscribe:peripheral];
}

/// Notifications from the measurement, once its descriptors are known.
- (void)subscribe:(CBPeripheral *)peripheral {
    [peripheral discoverDescriptorsForCharacteristic:self.measurement];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (characteristic == self.location) {
        if (error) printf("body sensor location: error %s %ld\n", error.domain.UTF8String, (long)error.code);
        else printf("body sensor location %s\n", hex(characteristic.value).UTF8String);
        unsigned char reset = 1;
        if (self.controlPoint)
            [peripheral writeValue:[NSData dataWithBytes:&reset length:1] forCharacteristic:self.controlPoint type:CBCharacteristicWriteWithResponse];
        else
            [self subscribe:peripheral];
    } else if (characteristic == self.measurement) {
        printf("measurement %s\n", hex(characteristic.value).UTF8String);
        if (++self.measurements == 3) [peripheral setNotifyValue:NO forCharacteristic:characteristic];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    printf("wrote %s, error %s\n", characteristic.UUID.UUIDString.UTF8String, error ? error.description.UTF8String : "none");
    [self subscribe:peripheral];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    for (CBDescriptor *descriptor in characteristic.descriptors) printf("descriptor %s\n", descriptor.UUID.UUIDString.UTF8String);
    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    printf("notifying %s\n", characteristic.isNotifying ? "YES" : "NO");
    if (!characteristic.isNotifying) [self.manager cancelPeripheralConnection:peripheral];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    printf("disconnected, error %s, peripheral state %ld\n", error ? error.description.UTF8String : "none", (long)peripheral.state);
    exit(0);
}

@end

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        CBUUID *shortForm = [CBUUID UUIDWithString:@"2a37"];
        CBUUID *longForm = [CBUUID UUIDWithString:@"00002A37-0000-1000-8000-00805F9B34FB"];
        printf("UUIDs %s %s equal %s\n", shortForm.UUIDString.UTF8String, longForm.UUIDString.UTF8String,
               [shortForm isEqual:longForm] ? "YES" : "NO");
        Central *central = [Central new];
        central.manager = [[CBCentralManager alloc] initWithDelegate:central queue:nil];
        printf("initial state %ld\n", (long)central.manager.state);
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
