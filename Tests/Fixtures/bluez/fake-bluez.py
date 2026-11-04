#!/usr/bin/env python3
"""A fake BlueZ for CoreBluetooth's tests: org.bluez on the bus in
DBUS_SYSTEM_BUS_ADDRESS, with one adapter, hci0, and one heart rate monitor
that it finds when discovering. Connecting resolves the monitor's GATT
database: the Heart Rate service (180D) with its measurement (2A37, notify,
with a client configuration descriptor), body sensor location (2A38, read)
and control point (2A39, write). Starting notifications sends three
measurements. It prints "ready" once it owns its name."""

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"
ADAPTER = "org.bluez.Adapter1"
DEVICE = "org.bluez.Device1"
SERVICE = "org.bluez.GattService1"
CHARACTERISTIC = "org.bluez.GattCharacteristic1"
DESCRIPTOR = "org.bluez.GattDescriptor1"

ADAPTER_PATH = "/org/bluez/hci0"
DEVICE_PATH = ADAPTER_PATH + "/dev_C0_FF_EE_00_11_22"
SERVICE_PATH = DEVICE_PATH + "/service0010"
MEASUREMENT_PATH = SERVICE_PATH + "/char0011"
CONFIGURATION_PATH = MEASUREMENT_PATH + "/desc0013"
LOCATION_PATH = SERVICE_PATH + "/char0014"
CONTROL_POINT_PATH = SERVICE_PATH + "/char0016"


def uuid(short):
    return "0000%s-0000-1000-8000-00805f9b34fb" % short


class Failed(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Failed"


class Root(dbus.service.Object):
    """The object manager at /, which knows every object."""

    def __init__(self, bus):
        super().__init__(bus, "/")
        self.objects = {}

    def add(self, obj):
        self.objects[obj.path] = obj
        self.InterfacesAdded(obj.path, {obj.interface: obj.props})

    def remove(self, obj):
        if self.objects.pop(obj.path, None) is not None:
            self.InterfacesRemoved(obj.path, [obj.interface])
            obj.remove_from_connection()

    @dbus.service.method(OBJECT_MANAGER, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        return {path: {obj.interface: obj.props} for path, obj in self.objects.items()}

    @dbus.service.signal(OBJECT_MANAGER, signature="oa{sa{sv}}")
    def InterfacesAdded(self, path, interfaces):
        pass

    @dbus.service.signal(OBJECT_MANAGER, signature="oas")
    def InterfacesRemoved(self, path, interfaces):
        pass


class Thing(dbus.service.Object):
    """An object with one BlueZ interface and its properties."""

    interface = None

    def __init__(self, bus, path, props):
        super().__init__(bus, path)
        self.bus = bus
        self.path = path
        self.props = props

    def change(self, **changed):
        self.props.update(changed)
        self.PropertiesChanged(self.interface, changed, [])

    @dbus.service.method(PROPERTIES, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.props[name]

    @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.props

    @dbus.service.method(PROPERTIES, in_signature="ssv")
    def Set(self, interface, name, value):
        self.change(**{name: value})

    @dbus.service.signal(PROPERTIES, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class Adapter(Thing):
    interface = ADAPTER

    def __init__(self, bus, root):
        super().__init__(bus, ADAPTER_PATH, {
            "Address": "00:1A:7D:DA:71:13", "Name": "perry", "Alias": "perry",
            "Powered": dbus.Boolean(True), "Discovering": dbus.Boolean(False),
        })
        self.root = root
        self.device = None

    @dbus.service.method(ADAPTER, in_signature="a{sv}")
    def SetDiscoveryFilter(self, filter):
        self.filter = filter

    @dbus.service.method(ADAPTER)
    def StartDiscovery(self):
        self.change(Discovering=dbus.Boolean(True))
        GLib.timeout_add(200, self.advertise)

    @dbus.service.method(ADAPTER)
    def StopDiscovery(self):
        self.change(Discovering=dbus.Boolean(False))

    def advertise(self):
        if self.device is None:
            self.device = Device(self.bus, self.root)
            self.root.add(self.device)
        else:
            self.device.change(RSSI=dbus.Int16(-52))
        return False


class Device(Thing):
    interface = DEVICE

    def __init__(self, bus, root):
        super().__init__(bus, DEVICE_PATH, {
            "Address": "C0:FF:EE:00:11:22", "AddressType": "random", "Name": "Pulse", "Alias": "Pulse",
            "Adapter": dbus.ObjectPath(ADAPTER_PATH), "RSSI": dbus.Int16(-52), "TxPower": dbus.Int16(4),
            "UUIDs": dbus.Array([uuid("180d")], signature="s"),
            "ManufacturerData": dbus.Dictionary({dbus.UInt16(0x004C): dbus.Array([1, 2, 3], signature="y")},
                                                signature="qv"),
            "Connected": dbus.Boolean(False), "ServicesResolved": dbus.Boolean(False),
            "Paired": dbus.Boolean(False), "Trusted": dbus.Boolean(False),
        })
        self.root = root
        self.gatt = []

    @dbus.service.method(DEVICE)
    def Connect(self):
        self.change(Connected=dbus.Boolean(True))
        GLib.timeout_add(100, self.resolve)

    @dbus.service.method(DEVICE)
    def Disconnect(self):
        for obj in reversed(self.gatt):
            self.root.remove(obj)
        self.gatt = []
        self.change(ServicesResolved=dbus.Boolean(False))
        self.change(Connected=dbus.Boolean(False))

    def resolve(self):
        bus = self.bus
        service = Gatt(bus, SERVICE, SERVICE_PATH, {
            "UUID": uuid("180d"), "Device": dbus.ObjectPath(DEVICE_PATH), "Primary": dbus.Boolean(True)})
        measurement = Characteristic(bus, MEASUREMENT_PATH, "2a37", ["notify"])
        configuration = Gatt(bus, DESCRIPTOR, CONFIGURATION_PATH, {
            "UUID": uuid("2902"), "Characteristic": dbus.ObjectPath(MEASUREMENT_PATH),
            "Value": dbus.Array([0, 0], signature="y")})
        location = Characteristic(bus, LOCATION_PATH, "2a38", ["read"], value=[1])
        control_point = Characteristic(bus, CONTROL_POINT_PATH, "2a39", ["write"])
        self.gatt = [service, measurement, configuration, location, control_point]
        for obj in self.gatt:
            self.root.add(obj)
        self.change(ServicesResolved=dbus.Boolean(True))
        return False


class Gatt(Thing):
    def __init__(self, bus, interface, path, props):
        self.interface = interface
        super().__init__(bus, path, props)

    @dbus.service.method(DESCRIPTOR, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        return self.props.get("Value", dbus.Array([], signature="y"))


class Characteristic(Thing):
    interface = CHARACTERISTIC

    def __init__(self, bus, path, short, flags, value=()):
        super().__init__(bus, path, {
            "UUID": uuid(short), "Service": dbus.ObjectPath(SERVICE_PATH),
            "Flags": dbus.Array(flags, signature="s"), "Notifying": dbus.Boolean(False),
            "Value": dbus.Array(list(value), signature="y"), "MTU": dbus.UInt16(185),
        })
        self.sent = 0

    @dbus.service.method(CHARACTERISTIC, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        return self.props["Value"]

    @dbus.service.method(CHARACTERISTIC, in_signature="aya{sv}")
    def WriteValue(self, value, options):
        if "write" not in self.props["Flags"] and "write-without-response" not in self.props["Flags"]:
            raise dbus.DBusException("Write not permitted", name="org.bluez.Error.NotPermitted")
        self.props["Value"] = dbus.Array(value, signature="y")

    @dbus.service.method(CHARACTERISTIC)
    def StartNotify(self):
        self.change(Notifying=dbus.Boolean(True))
        self.sent = 0
        GLib.timeout_add(100, self.notify)

    @dbus.service.method(CHARACTERISTIC)
    def StopNotify(self):
        self.change(Notifying=dbus.Boolean(False))

    def notify(self):
        if not self.props["Notifying"] or self.sent == 3:
            return False
        self.sent += 1
        self.change(Value=dbus.Array([0x00, 60 + self.sent], signature="y"))
        return True


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(__import__("os").environ["DBUS_SYSTEM_BUS_ADDRESS"])
    name = dbus.service.BusName("org.bluez", bus)
    root = Root(bus)
    root.add(Adapter(bus, root))
    print("ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
