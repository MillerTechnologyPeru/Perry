import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSUnit, NSDimension and the unit classes of the physical quantities
// (NSUnitLength, NSUnitSpeed, ...), NSUnitConverter and its linear
// converter, and NSMeasurement: what Swift's Measurement and Unit are
// built on. The units of each class are a table, answered by class methods
// ("+[NSUnitLength kilometers]") that give one shared instance each.

// MARK: - Storage

final class UnitLock: @unchecked Sendable {
    private var mutex = pthread_mutex_t()
    init() { pthread_mutex_init(&mutex, nil) }
    func withLock<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        return body()
    }
}

final class UnitStorage {
    var symbol = ""
    /// The converter of a dimension, retained.
    var converter: id?

    deinit {
        if let converter { ObjC.release(converter) }
    }
}

final class LinearConverterStorage {
    var coefficient = 1.0
    var constant = 0.0
}

final class MeasurementStorage {
    var value = 0.0
    /// Retained.
    var unit: id?

    deinit {
        if let unit { ObjC.release(unit) }
    }
}

enum Units {
    nonisolated(unsafe) static var unitClass: Class!
    nonisolated(unsafe) static var converterClass: Class!
    nonisolated(unsafe) static var linearClass: Class!
    nonisolated(unsafe) static var measurementClass: Class!

    static func storage(_ object: id) -> UnitStorage {
        if let storage = Storage.get(object, as: UnitStorage.self) { return storage }
        let storage = UnitStorage()
        Storage.set(object, storage)
        return storage
    }

    static func linear(_ object: id) -> LinearConverterStorage {
        if let storage = Storage.get(object, as: LinearConverterStorage.self) { return storage }
        let storage = LinearConverterStorage()
        Storage.set(object, storage)
        return storage
    }

    static func measurement(_ object: id) -> MeasurementStorage {
        if let storage = Storage.get(object, as: MeasurementStorage.self) { return storage }
        let storage = MeasurementStorage()
        Storage.set(object, storage)
        return storage
    }

    static func named(_ name: String) -> Class? {
        name.withCString { ObjC.getClass($0) }
    }

    /// The result of a message that takes and answers a double.
    static func send(_ receiver: id, _ name: String, _ value: Double) -> Double {
        typealias Fn = @convention(c) (id, SEL, Double) -> Double
        return unsafeBitCast(ObjC.msgSend, to: Fn.self)(receiver, ObjC.selector(name), value)
    }

    static func symbol(of unit: id) -> String {
        Strings.value(of: ObjC.send(unit, ObjC.selector("symbol"))) ?? storage(unit).symbol
    }

    /// The value of `value` in `unit`, in the base unit of its dimension.
    static func baseValue(_ value: Double, of unit: id) -> Double {
        guard let converter = ObjC.send(unit, ObjC.selector("converter")) else { return value }
        return send(converter, "baseUnitValueFromValue:", value)
    }

    static func value(fromBase value: Double, in unit: id) -> Double {
        guard let converter = ObjC.send(unit, ObjC.selector("converter")) else { return value }
        return send(converter, "valueFromBaseUnitValue:", value)
    }

    /// A linear converter.
    static func makeConverter(coefficient: Double, constant: Double) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(linearClass)) else { return nil }
        let state = linear(object)
        state.coefficient = coefficient
        state.constant = constant
        return object
    }
}

// MARK: - NSUnit

/// NSUnit: a symbol.
@ObjCClass("NSUnit")
public class NSUnit: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Units.unitClass = cls.storage
    }

    var unit: UnitStorage { Units.storage(objcObject) }

    @ObjCMethod("initWithSymbol:")
    func initialize(symbol: String?) -> Self {
        unit.symbol = symbol ?? ""
        return self
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = unit
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Units.unitClass)
    }

    @ObjCMethod("symbol") func symbol() -> String { unit.symbol }
    @ObjCMethod("description") func description() -> String { unit.symbol }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        if other.objcObject == objcObject { return true }
        guard ObjC.isKind(other.objcObject, of: Units.unitClass),
              ObjC.objectGetClass(other.objcObject) == ObjC.objectGetClass(objcObject) else { return false }
        return Units.symbol(of: other.objcObject) == unit.symbol
    }

    @ObjCMethod("hash") func hash() -> UInt { Strings.hash(unit.symbol) }
}

/// NSUnitConverter: the way to and from a dimension's base unit.
@ObjCClass("NSUnitConverter")
public class NSUnitConverter: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Units.converterClass = cls.storage
    }

    @ObjCMethod("baseUnitValueFromValue:") func baseUnitValue(fromValue value: Double) -> Double { value }
    @ObjCMethod("valueFromBaseUnitValue:") func value(fromBaseUnitValue value: Double) -> Double { value }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Units.converterClass)
    }
}

/// NSUnitConverterLinear: value × coefficient + constant.
@ObjCClass("NSUnitConverterLinear")
public class NSUnitConverterLinear: NSUnitConverter {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Units.linearClass = cls.storage
    }

    var state: LinearConverterStorage { Units.linear(objcObject) }

    @ObjCMethod("initWithCoefficient:")
    func initialize(coefficient: Double) -> Self {
        state.coefficient = coefficient
        return self
    }

    @ObjCMethod("initWithCoefficient:constant:")
    func initialize(coefficient: Double, constant: Double) -> Self {
        state.coefficient = coefficient
        state.constant = constant
        return self
    }

    @ObjCMethod("coefficient") func coefficient() -> Double { state.coefficient }
    @ObjCMethod("constant") func constant() -> Double { state.constant }

    @ObjCMethod("baseUnitValueFromValue:")
    override func baseUnitValue(fromValue value: Double) -> Double { value * state.coefficient + state.constant }

    @ObjCMethod("valueFromBaseUnitValue:")
    override func value(fromBaseUnitValue value: Double) -> Double { (value - state.constant) / state.coefficient }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, ObjC.objectGetClass(other.objcObject) == ObjC.objectGetClass(objcObject) else { return false }
        let theirs = Units.linear(other.objcObject)
        return theirs.coefficient == state.coefficient && theirs.constant == state.constant
    }
}

/// NSDimension: a unit that converts to the base unit of its quantity.
@ObjCClass("NSDimension")
public class NSDimension: NSUnit {
    @ObjCMethod("initWithSymbol:converter:")
    func initialize(symbol: String?, converter: ObjCObject?) -> Self {
        unit.symbol = symbol ?? ""
        if let old = unit.converter { ObjC.release(old) }
        unit.converter = converter.flatMap { ObjC.retain($0.objcObject) }
        return self
    }

    @ObjCMethod("converter")
    func converter() -> UnsafeMutableRawPointer? { unit.converter }

    @ObjCClassMethod("unitWithSymbol:converter:")
    static func unit(_ cls: ObjCClass, symbol: String?, converter: ObjCObject?) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(cls.storage)) else { return nil }
        let state = Units.storage(object)
        state.symbol = symbol ?? ""
        state.converter = converter.flatMap { ObjC.retain($0.objcObject) }
        return ObjC.autorelease(object)
    }
}

// MARK: - The quantities

/// A unit of a quantity: its class method, symbol and conversion to the
/// base unit.
struct UnitSpec {
    let selector: String
    let symbol: String
    let coefficient: Double
    var constant = 0.0
    var name: (singular: String, plural: String)?

    init(_ selector: String, _ symbol: String, _ coefficient: Double, constant: Double = 0, name: (String, String)? = nil) {
        self.selector = selector
        self.symbol = symbol
        self.coefficient = coefficient
        self.constant = constant
        self.name = name.map { (singular: $0.0, plural: $0.1) }
    }
}

enum UnitTables {
    /// The base unit's selector and the units of each class.
    static let tables: [String: (base: String, units: [UnitSpec])] = [
        "NSUnitLength": ("meters", [
            UnitSpec("megameters", "Mm", 1e6, name: ("megameter", "megameters")),
            UnitSpec("kilometers", "km", 1000, name: ("kilometer", "kilometers")),
            UnitSpec("hectometers", "hm", 100, name: ("hectometer", "hectometers")),
            UnitSpec("decameters", "dam", 10, name: ("decameter", "decameters")),
            UnitSpec("meters", "m", 1, name: ("meter", "meters")),
            UnitSpec("decimeters", "dm", 0.1, name: ("decimeter", "decimeters")),
            UnitSpec("centimeters", "cm", 0.01, name: ("centimeter", "centimeters")),
            UnitSpec("millimeters", "mm", 0.001, name: ("millimeter", "millimeters")),
            UnitSpec("micrometers", "µm", 1e-6, name: ("micrometer", "micrometers")),
            UnitSpec("nanometers", "nm", 1e-9, name: ("nanometer", "nanometers")),
            UnitSpec("picometers", "pm", 1e-12, name: ("picometer", "picometers")),
            UnitSpec("inches", "in", 0.0254, name: ("inch", "inches")),
            UnitSpec("feet", "ft", 0.3048, name: ("foot", "feet")),
            UnitSpec("yards", "yd", 0.9144, name: ("yard", "yards")),
            UnitSpec("miles", "mi", 1609.344, name: ("mile", "miles")),
            UnitSpec("scandinavianMiles", "smi", 10000, name: ("Scandinavian mile", "Scandinavian miles")),
            UnitSpec("lightyears", "ly", 9.4607304725808e15, name: ("light year", "light years")),
            UnitSpec("nauticalMiles", "NM", 1852, name: ("nautical mile", "nautical miles")),
            UnitSpec("fathoms", "fathom", 1.8288, name: ("fathom", "fathoms")),
            UnitSpec("furlongs", "furlong", 201.168, name: ("furlong", "furlongs")),
            UnitSpec("astronomicalUnits", "ua", 1.495978707e11, name: ("astronomical unit", "astronomical units")),
            UnitSpec("parsecs", "pc", 3.0856775814913673e16, name: ("parsec", "parsecs")),
        ]),
        "NSUnitSpeed": ("metersPerSecond", [
            UnitSpec("metersPerSecond", "m/s", 1, name: ("meter per second", "meters per second")),
            UnitSpec("kilometersPerHour", "km/h", 0.277777778, name: ("kilometer per hour", "kilometers per hour")),
            UnitSpec("milesPerHour", "mph", 0.44704, name: ("mile per hour", "miles per hour")),
            UnitSpec("knots", "kn", 0.514444444, name: ("knot", "knots")),
        ]),
        "NSUnitDuration": ("seconds", [
            UnitSpec("seconds", "s", 1, name: ("second", "seconds")),
            UnitSpec("milliseconds", "ms", 0.001, name: ("millisecond", "milliseconds")),
            UnitSpec("microseconds", "µs", 1e-6, name: ("microsecond", "microseconds")),
            UnitSpec("nanoseconds", "ns", 1e-9, name: ("nanosecond", "nanoseconds")),
            UnitSpec("picoseconds", "ps", 1e-12, name: ("picosecond", "picoseconds")),
            UnitSpec("minutes", "min", 60, name: ("minute", "minutes")),
            UnitSpec("hours", "hr", 3600, name: ("hour", "hours")),
        ]),
        "NSUnitMass": ("kilograms", [
            UnitSpec("kilograms", "kg", 1, name: ("kilogram", "kilograms")),
            UnitSpec("grams", "g", 0.001, name: ("gram", "grams")),
            UnitSpec("decigrams", "dg", 0.0001, name: ("decigram", "decigrams")),
            UnitSpec("centigrams", "cg", 1e-5, name: ("centigram", "centigrams")),
            UnitSpec("milligrams", "mg", 1e-6, name: ("milligram", "milligrams")),
            UnitSpec("micrograms", "µg", 1e-9, name: ("microgram", "micrograms")),
            UnitSpec("nanograms", "ng", 1e-12, name: ("nanogram", "nanograms")),
            UnitSpec("picograms", "pg", 1e-15, name: ("picogram", "picograms")),
            UnitSpec("ounces", "oz", 0.0283495, name: ("ounce", "ounces")),
            UnitSpec("poundsMass", "lb", 0.453592, name: ("pound", "pounds")),
            UnitSpec("stones", "st", 6.35029, name: ("stone", "stones")),
            UnitSpec("metricTons", "t", 1000, name: ("metric ton", "metric tons")),
            UnitSpec("shortTons", "ton", 907.185, name: ("ton", "tons")),
            UnitSpec("carats", "ct", 0.0002, name: ("carat", "carats")),
            UnitSpec("ouncesTroy", "oz t", 0.03110348, name: ("troy ounce", "troy ounces")),
            UnitSpec("slugs", "slug", 14.5939, name: ("slug", "slugs")),
        ]),
        "NSUnitEnergy": ("joules", [
            UnitSpec("kilojoules", "kJ", 1000, name: ("kilojoule", "kilojoules")),
            UnitSpec("joules", "J", 1, name: ("joule", "joules")),
            UnitSpec("kilocalories", "kCal", 4184, name: ("kilocalorie", "kilocalories")),
            UnitSpec("calories", "cal", 4.184, name: ("calorie", "calories")),
            UnitSpec("kilowattHours", "kWh", 3600000, name: ("kilowatt hour", "kilowatt hours")),
        ]),
        "NSUnitTemperature": ("kelvin", [
            UnitSpec("kelvin", "K", 1, name: ("kelvin", "kelvin")),
            UnitSpec("celsius", "°C", 1, constant: 273.15, name: ("degree Celsius", "degrees Celsius")),
            UnitSpec("fahrenheit", "°F", 0.555555555555556, constant: 255.372222222222, name: ("degree Fahrenheit", "degrees Fahrenheit")),
        ]),
        "NSUnitAngle": ("degrees", [
            UnitSpec("degrees", "°", 1, name: ("degree", "degrees")),
            UnitSpec("arcMinutes", "′", 1.0 / 60, name: ("arcminute", "arcminutes")),
            UnitSpec("arcSeconds", "″", 1.0 / 3600, name: ("arcsecond", "arcseconds")),
            UnitSpec("radians", "rad", 57.2957795131, name: ("radian", "radians")),
            UnitSpec("gradians", "grad", 0.9, name: ("gradian", "gradians")),
            UnitSpec("revolutions", "rev", 360, name: ("revolution", "revolutions")),
        ]),
        "NSUnitPower": ("watts", [
            UnitSpec("terawatts", "TW", 1e12, name: ("terawatt", "terawatts")),
            UnitSpec("gigawatts", "GW", 1e9, name: ("gigawatt", "gigawatts")),
            UnitSpec("megawatts", "MW", 1e6, name: ("megawatt", "megawatts")),
            UnitSpec("kilowatts", "kW", 1000, name: ("kilowatt", "kilowatts")),
            UnitSpec("watts", "W", 1, name: ("watt", "watts")),
            UnitSpec("milliwatts", "mW", 0.001, name: ("milliwatt", "milliwatts")),
            UnitSpec("microwatts", "µW", 1e-6, name: ("microwatt", "microwatts")),
            UnitSpec("nanowatts", "nW", 1e-9, name: ("nanowatt", "nanowatts")),
            UnitSpec("picowatts", "pW", 1e-12, name: ("picowatt", "picowatts")),
            UnitSpec("femtowatts", "fW", 1e-15, name: ("femtowatt", "femtowatts")),
            UnitSpec("horsepower", "hp", 745.7, name: ("horsepower", "horsepower")),
        ]),
        "NSUnitPressure": ("newtonsPerMetersSquared", [
            UnitSpec("newtonsPerMetersSquared", "N/m²", 1, name: ("newton per square meter", "newtons per square meter")),
            UnitSpec("gigapascals", "GPa", 1e9, name: ("gigapascal", "gigapascals")),
            UnitSpec("megapascals", "MPa", 1e6, name: ("megapascal", "megapascals")),
            UnitSpec("kilopascals", "kPa", 1000, name: ("kilopascal", "kilopascals")),
            UnitSpec("hectopascals", "hPa", 100, name: ("hectopascal", "hectopascals")),
            UnitSpec("inchesOfMercury", "inHg", 3386.39, name: ("inch of mercury", "inches of mercury")),
            UnitSpec("bars", "bar", 1e5, name: ("bar", "bars")),
            UnitSpec("millibars", "mbar", 100, name: ("millibar", "millibars")),
            UnitSpec("millimetersOfMercury", "mmHg", 133.322, name: ("millimeter of mercury", "millimeters of mercury")),
            UnitSpec("poundsForcePerSquareInch", "psi", 6894.76, name: ("pound per square inch", "pounds per square inch")),
        ]),
        "NSUnitAcceleration": ("metersPerSecondSquared", [
            UnitSpec("metersPerSecondSquared", "m/s²", 1, name: ("meter per second squared", "meters per second squared")),
            UnitSpec("gravity", "g", 9.81, name: ("g-force", "g-force")),
        ]),
        "NSUnitArea": ("squareMeters", [
            UnitSpec("squareMegameters", "Mm²", 1e12, name: ("square megameter", "square megameters")),
            UnitSpec("squareKilometers", "km²", 1e6, name: ("square kilometer", "square kilometers")),
            UnitSpec("squareMeters", "m²", 1, name: ("square meter", "square meters")),
            UnitSpec("squareCentimeters", "cm²", 1e-4, name: ("square centimeter", "square centimeters")),
            UnitSpec("squareMillimeters", "mm²", 1e-6, name: ("square millimeter", "square millimeters")),
            UnitSpec("squareInches", "in²", 0.00064516, name: ("square inch", "square inches")),
            UnitSpec("squareFeet", "ft²", 0.092903, name: ("square foot", "square feet")),
            UnitSpec("squareYards", "yd²", 0.836127, name: ("square yard", "square yards")),
            UnitSpec("squareMiles", "mi²", 2589988.11, name: ("square mile", "square miles")),
            UnitSpec("acres", "ac", 4046.86, name: ("acre", "acres")),
            UnitSpec("ares", "a", 100, name: ("are", "ares")),
            UnitSpec("hectares", "ha", 10000, name: ("hectare", "hectares")),
        ]),
        "NSUnitVolume": ("liters", [
            UnitSpec("megaliters", "ML", 1e6, name: ("megaliter", "megaliters")),
            UnitSpec("kiloliters", "kL", 1000, name: ("kiloliter", "kiloliters")),
            UnitSpec("liters", "L", 1, name: ("liter", "liters")),
            UnitSpec("deciliters", "dL", 0.1, name: ("deciliter", "deciliters")),
            UnitSpec("centiliters", "cL", 0.01, name: ("centiliter", "centiliters")),
            UnitSpec("milliliters", "mL", 0.001, name: ("milliliter", "milliliters")),
            UnitSpec("cubicMeters", "m³", 1000, name: ("cubic meter", "cubic meters")),
            UnitSpec("cubicCentimeters", "cm³", 0.001, name: ("cubic centimeter", "cubic centimeters")),
            UnitSpec("cubicInches", "in³", 0.0163871, name: ("cubic inch", "cubic inches")),
            UnitSpec("cubicFeet", "ft³", 28.3168, name: ("cubic foot", "cubic feet")),
            UnitSpec("teaspoons", "tsp", 0.00492892, name: ("teaspoon", "teaspoons")),
            UnitSpec("tablespoons", "tbsp", 0.0147868, name: ("tablespoon", "tablespoons")),
            UnitSpec("fluidOunces", "fl oz", 0.0295735, name: ("fluid ounce", "fluid ounces")),
            UnitSpec("cups", "cup", 0.24, name: ("cup", "cups")),
            UnitSpec("pints", "pt", 0.473176, name: ("pint", "pints")),
            UnitSpec("quarts", "qt", 0.946353, name: ("quart", "quarts")),
            UnitSpec("gallons", "gal", 3.78541, name: ("gallon", "gallons")),
        ]),
        "NSUnitConcentrationMass": ("gramsPerLiter", [
            UnitSpec("gramsPerLiter", "g/L", 1, name: ("gram per liter", "grams per liter")),
            UnitSpec("milligramsPerDeciliter", "mg/dL", 0.01, name: ("milligram per deciliter", "milligrams per deciliter")),
        ]),
        "NSUnitElectricPotentialDifference": ("volts", [
            UnitSpec("megavolts", "MV", 1e6, name: ("megavolt", "megavolts")),
            UnitSpec("kilovolts", "kV", 1000, name: ("kilovolt", "kilovolts")),
            UnitSpec("volts", "V", 1, name: ("volt", "volts")),
            UnitSpec("millivolts", "mV", 0.001, name: ("millivolt", "millivolts")),
            UnitSpec("microvolts", "µV", 1e-6, name: ("microvolt", "microvolts")),
        ]),
        "NSUnitFrequency": ("hertz", [
            UnitSpec("terahertz", "THz", 1e12, name: ("terahertz", "terahertz")),
            UnitSpec("gigahertz", "GHz", 1e9, name: ("gigahertz", "gigahertz")),
            UnitSpec("megahertz", "MHz", 1e6, name: ("megahertz", "megahertz")),
            UnitSpec("kilohertz", "kHz", 1000, name: ("kilohertz", "kilohertz")),
            UnitSpec("hertz", "Hz", 1, name: ("hertz", "hertz")),
            UnitSpec("millihertz", "mHz", 0.001, name: ("millihertz", "millihertz")),
            UnitSpec("microhertz", "µHz", 1e-6, name: ("microhertz", "microhertz")),
            UnitSpec("nanohertz", "nHz", 1e-9, name: ("nanohertz", "nanohertz")),
            UnitSpec("framesPerSecond", "fps", 1, name: ("frame per second", "frames per second")),
        ]),
        "NSUnitInformationStorage": ("bytes", [
            UnitSpec("bytes", "byte", 1, name: ("byte", "bytes")),
            UnitSpec("bits", "bit", 0.125, name: ("bit", "bits")),
            UnitSpec("nibbles", "nibble", 0.5, name: ("nibble", "nibbles")),
            UnitSpec("kilobytes", "kB", 1000, name: ("kilobyte", "kilobytes")),
            UnitSpec("megabytes", "MB", 1e6, name: ("megabyte", "megabytes")),
            UnitSpec("gigabytes", "GB", 1e9, name: ("gigabyte", "gigabytes")),
            UnitSpec("terabytes", "TB", 1e12, name: ("terabyte", "terabytes")),
            UnitSpec("kibibytes", "KiB", 1024, name: ("kibibyte", "kibibytes")),
            UnitSpec("mebibytes", "MiB", 1048576, name: ("mebibyte", "mebibytes")),
            UnitSpec("gibibytes", "GiB", 1073741824, name: ("gibibyte", "gibibytes")),
        ]),
    ]

    /// The shared instance of each unit, by class and selector.
    nonisolated(unsafe) private static var shared: [String: id] = [:]
    private static let lock = UnitLock()

    /// The long names of the units given, by symbol.
    nonisolated(unsafe) static var names: [String: (singular: String, plural: String)] = {
        var found: [String: (singular: String, plural: String)] = [:]
        for table in tables.values {
            for unit in table.units {
                if let name = unit.name, found[unit.symbol] == nil { found[unit.symbol] = name }
            }
        }
        return found
    }()

    /// The IMP of every unit's class method: a class and a selector tell the
    /// unit.
    static let unitMethod: @convention(c) (id?, SEL?) -> id? = { receiver, selector in
        guard let receiver, let selector else { return nil }
        let name = String(cString: selector)
        // The class the table is of: the receiver, or the nearest class above it with one.
        var current: Class? = receiver.assumingMemoryBound(to: perry_class_storage.self)
        var found: (table: (base: String, units: [UnitSpec]), className: String)?
        while let cls = current {
            if let className = classNames[UInt(bitPattern: cls)], let table = tables[className] {
                found = (table, className)
                break
            }
            current = cls.pointee.superclass
        }
        guard let (table, className) = found else { return nil }
        let wanted = name == "baseUnit" ? table.base : name
        guard let spec = table.units.first(where: { $0.selector == wanted }) else { return nil }
        let key = className + "." + spec.selector
        return lock.withLock { () -> id? in
            if let existing = shared[key] { return existing }
            guard let cls = classes[className],
                  let object = Storage.allocate(UnsafeMutableRawPointer(cls)),
                  let converter = Units.makeConverter(coefficient: spec.coefficient, constant: spec.constant) else { return nil }
            let state = Units.storage(object)
            state.symbol = spec.symbol
            state.converter = converter
            shared[key] = object
            return object
        }
    }

    /// The tables' classes, by name and by address.
    nonisolated(unsafe) static var classes: [String: Class] = [:]
    nonisolated(unsafe) static var classNames: [UInt: String] = [:]

    /// Adds a quantity's unit class methods.
    static func install(_ cls: ObjCClass, _ name: String) {
        guard let table = tables[name] else { return }
        classes[name] = cls.storage
        classNames[UInt(bitPattern: cls.storage)] = name
        for unit in table.units {
            cls.addMethod(unit.selector, types: "@16@0:8", implementation: unsafeBitCast(unitMethod, to: UnsafeRawPointer.self), isClassMethod: true)
        }
        cls.addMethod("baseUnit", types: "@16@0:8", implementation: unsafeBitCast(unitMethod, to: UnsafeRawPointer.self), isClassMethod: true)
    }
}

@ObjCClass("NSUnitLength") public class NSUnitLength: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitLength") }
}
@ObjCClass("NSUnitSpeed") public class NSUnitSpeed: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitSpeed") }
}
@ObjCClass("NSUnitDuration") public class NSUnitDuration: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitDuration") }
}
@ObjCClass("NSUnitMass") public class NSUnitMass: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitMass") }
}
@ObjCClass("NSUnitEnergy") public class NSUnitEnergy: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitEnergy") }
}
@ObjCClass("NSUnitTemperature") public class NSUnitTemperature: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitTemperature") }
}
@ObjCClass("NSUnitAngle") public class NSUnitAngle: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitAngle") }
}
@ObjCClass("NSUnitPower") public class NSUnitPower: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitPower") }
}
@ObjCClass("NSUnitPressure") public class NSUnitPressure: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitPressure") }
}
@ObjCClass("NSUnitAcceleration") public class NSUnitAcceleration: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitAcceleration") }
}
@ObjCClass("NSUnitArea") public class NSUnitArea: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitArea") }
}
@ObjCClass("NSUnitVolume") public class NSUnitVolume: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitVolume") }
}
@ObjCClass("NSUnitConcentrationMass") public class NSUnitConcentrationMass: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitConcentrationMass") }
}
@ObjCClass("NSUnitElectricPotentialDifference") public class NSUnitElectricPotentialDifference: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitElectricPotentialDifference") }
}
@ObjCClass("NSUnitFrequency") public class NSUnitFrequency: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitFrequency") }
}
@ObjCClass("NSUnitInformationStorage") public class NSUnitInformationStorage: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitInformationStorage") }
}

// MARK: - NSMeasurement

/// NSMeasurement: a value in a unit.
@ObjCClass("NSMeasurement")
public class NSMeasurement: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Units.measurementClass = cls.storage
    }

    var measurement: MeasurementStorage { Units.measurement(objcObject) }

    @ObjCMethod("initWithDoubleValue:unit:")
    func initialize(doubleValue: Double, unit: ObjCObject?) -> Self {
        measurement.value = doubleValue
        if let old = measurement.unit { ObjC.release(old) }
        measurement.unit = unit.flatMap { ObjC.retain($0.objcObject) }
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Units.measurementClass)
    }

    @ObjCMethod("doubleValue") func doubleValue() -> Double { measurement.value }
    @ObjCMethod("unit") func unit() -> UnsafeMutableRawPointer? { measurement.unit }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    @ObjCMethod("canBeConvertedToUnit:")
    func canBeConverted(to unit: ObjCObject?) -> Bool {
        guard let mine = measurement.unit, let unit else { return false }
        return Units.convertible(mine, unit.objcObject)
    }

    @ObjCMethod("measurementByConvertingToUnit:")
    func converting(to unit: ObjCObject) -> UnsafeMutableRawPointer? {
        guard let mine = measurement.unit, Units.convertible(mine, unit.objcObject) else {
            foundationFatal("Cannot convert \(Units.symbol(of: measurement.unit ?? objcObject)) to \(Units.symbol(of: unit.objcObject))")
        }
        let base = Units.baseValue(measurement.value, of: mine)
        return Units.autoreleasedMeasurement(Units.value(fromBase: base, in: unit.objcObject), unit.objcObject)
    }

    @ObjCMethod("measurementByAddingMeasurement:")
    func adding(_ other: ObjCObject) -> UnsafeMutableRawPointer? { combined(other, sign: 1) }

    @ObjCMethod("measurementBySubtractingMeasurement:")
    func subtracting(_ other: ObjCObject) -> UnsafeMutableRawPointer? { combined(other, sign: -1) }

    private func combined(_ other: ObjCObject, sign: Double) -> UnsafeMutableRawPointer? {
        guard let mine = measurement.unit else { return nil }
        let theirs = Units.measurement(other.objcObject)
        guard let theirUnit = theirs.unit else { return nil }
        if ObjC.send(mine, ObjC.selector("isEqual:"), theirUnit) != nil, Units.sameUnit(mine, theirUnit) {
            return Units.autoreleasedMeasurement(measurement.value + sign * theirs.value, mine)
        }
        // Dimensions meet in their base unit.
        let sum = Units.baseValue(measurement.value, of: mine) + sign * Units.baseValue(theirs.value, of: theirUnit)
        guard let base = Units.baseUnit(of: mine) else { return nil }
        return Units.autoreleasedMeasurement(sum, base)
    }

    @ObjCMethod("description")
    func description() -> String {
        "\(Units.format(measurement.value)) \(measurement.unit.map(Units.symbol(of:)) ?? "")"
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, ObjC.isKind(other.objcObject, of: Units.measurementClass),
              let mine = measurement.unit, let theirUnit = Units.measurement(other.objcObject).unit else { return false }
        let theirs = Units.measurement(other.objcObject).value
        if Units.sameUnit(mine, theirUnit) { return theirs == measurement.value }
        guard Units.convertible(mine, theirUnit) else { return false }
        return Units.baseValue(measurement.value, of: mine) == Units.baseValue(theirs, of: theirUnit)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(truncatingIfNeeded: measurement.value.bitPattern) }
}

extension Units {
    /// Whether two units are of one quantity: dimensions of one class, or
    /// the same unit.
    static func convertible(_ first: id, _ second: id) -> Bool {
        if sameUnit(first, second) { return true }
        guard let dimension = named("NSDimension"), ObjC.isKind(first, of: dimension), ObjC.isKind(second, of: dimension) else { return false }
        return baseUnit(of: first).map { base in baseUnit(of: second).map { sameUnit($0, base) } ?? false } ?? false
    }

    static func sameUnit(_ first: id, _ second: id) -> Bool {
        first == second || ObjC.sendBool(first, ObjC.selector("isEqual:"), second)
    }

    /// The base unit of a dimension's class, by its class method.
    static func baseUnit(of unit: id) -> id? {
        var current = ObjC.objectGetClass(unit)
        while let c = current {
            if UnitTables.classNames[UInt(bitPattern: c)] != nil {
                return ObjC.send(UnsafeMutableRawPointer(c), ObjC.selector("baseUnit"))
            }
            current = c.pointee.superclass
        }
        return nil
    }

    static func autoreleasedMeasurement(_ value: Double, _ unit: id) -> id? {
        guard let cls = measurementClass, let object = Storage.allocate(UnsafeMutableRawPointer(cls)) else { return nil }
        let state = measurement(object)
        state.value = value
        state.unit = ObjC.retain(unit)
        return ObjC.autorelease(object)
    }

    /// A number as a formatter without settings writes it: up to three
    /// fraction digits, and digits grouped by thousands.
    static func format(_ value: Double, maximumFractionDigits: Int = 3) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-∞" : "∞" }
        var buffer = [CChar](repeating: 0, count: 64)
        _ = withVaList([maximumFractionDigits, abs(value)]) { vsnprintf(&buffer, buffer.count, "%.*f", $0) }
        var text = String(cString: buffer)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        var whole = text, fraction = ""
        if let dot = text.firstIndex(of: ".") {
            whole = String(text[..<dot])
            fraction = String(text[dot...])
        }
        var grouped = ""
        for (index, digit) in whole.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        let result = String(grouped.reversed()) + fraction
        return value < 0 && result != "0" ? "-" + result : result
    }
}

// MARK: - NSMeasurementFormatter

final class MeasurementFormatterStorage {
    var unitOptions: UInt = 0
    /// NSFormattingUnitStyle: short 1, medium 2, long 3.
    var unitStyle = 2
    var locale: id?
    var numberFormatter: id?

    deinit {
        if let locale { ObjC.release(locale) }
        if let numberFormatter { ObjC.release(numberFormatter) }
    }
}

/// NSMeasurementFormatter: a measurement as text, "5.2 km".
@ObjCClass("NSMeasurementFormatter")
public class NSMeasurementFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: MeasurementFormatterStorage {
        if let state = Storage.get(objcObject, as: MeasurementFormatterStorage.self) { return state }
        let state = MeasurementFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMeasurementFormatter.formatterClass)
    }

    @ObjCMethod("unitOptions") func unitOptions() -> UInt { state.unitOptions }
    @ObjCMethod("setUnitOptions:") func setUnitOptions(_ options: UInt) { state.unitOptions = options }
    @ObjCMethod("unitStyle") func unitStyle() -> Int { state.unitStyle }
    @ObjCMethod("setUnitStyle:") func setUnitStyle(_ style: Int) { state.unitStyle = style }

    @ObjCMethod("locale")
    func locale() -> UnsafeMutableRawPointer {
        state.locale ?? Locales.autoreleased(Locale.current)
    }

    @ObjCMethod("setLocale:")
    func setLocale(_ locale: ObjCObject?) {
        if let old = state.locale { ObjC.release(old) }
        state.locale = locale.flatMap { ObjC.retain($0.objcObject) }
    }

    @ObjCMethod("numberFormatter")
    func numberFormatter() -> UnsafeMutableRawPointer? {
        if state.numberFormatter == nil, let cls = Units.named("NSNumberFormatter") {
            if let made = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")), ObjC.selector("init")) {
                // Up to three fraction digits, as on Darwin.
                typealias SetInt = @convention(c) (id, SEL, UInt) -> Void
                typealias SetStyle = @convention(c) (id, SEL, Int) -> Void
                unsafeBitCast(ObjC.msgSend, to: SetStyle.self)(made, ObjC.selector("setNumberStyle:"), 1)
                unsafeBitCast(ObjC.msgSend, to: SetInt.self)(made, ObjC.selector("setMaximumFractionDigits:"), 3)
                state.numberFormatter = made
            }
        }
        return state.numberFormatter
    }

    @ObjCMethod("setNumberFormatter:")
    func setNumberFormatter(_ formatter: ObjCObject?) {
        if let old = state.numberFormatter { ObjC.release(old) }
        state.numberFormatter = formatter.flatMap { ObjC.retain($0.objcObject) }
    }

    /// A unit's text in the style: its symbol, or its name in the long style.
    private func text(of unit: id, for value: Double?) -> String {
        let symbol = Units.symbol(of: unit)
        guard state.unitStyle == 3, let name = UnitTables.names[symbol] else { return symbol }
        return value == 1 ? name.singular : name.plural
    }

    @ObjCMethod("stringFromUnit:")
    func string(fromUnit unit: ObjCObject) -> String { text(of: unit.objcObject, for: nil) }

    @ObjCMethod("stringFromMeasurement:")
    func string(fromMeasurement measurement: ObjCObject) -> String {
        let data = Units.measurement(measurement.objcObject)
        guard let unit = data.unit else { return Units.format(data.value) }
        let number: String
        if let formatter = numberFormatter(),
           let text = Strings.value(of: ObjC.send(formatter, ObjC.selector("stringFromNumber:"), Numbers.make(nil, .double(data.value)))) {
            number = text
        } else {
            number = Units.format(data.value)
        }
        let symbol = Units.symbol(of: unit)
        // Temperatures can go without their unit.
        if state.unitOptions & 4 != 0, symbol.hasPrefix("°") { return number + "°" }
        let name = text(of: unit, for: data.value)
        return symbol.hasPrefix("°") && state.unitStyle != 3 ? number + name : number + " " + name
    }

    @ObjCMethod("stringForObjectValue:")
    func string(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Units.measurementClass) else { return nil }
        return string(fromMeasurement: value)
    }
}

// MARK: - NSLengthFormatter

final class LengthFormatterStorage {
    var unitStyle = 2
    var forPersonHeightUse = false
    var numberFormatter: id?

    deinit {
        if let numberFormatter { ObjC.release(numberFormatter) }
    }
}

extension Units {
    /// A number formatter that writes up to three fraction digits, retained.
    static func makeNumberFormatter() -> id? {
        guard let cls = named("NSNumberFormatter"),
              let made = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")), ObjC.selector("init")) else { return nil }
        typealias SetInt = @convention(c) (id, SEL, UInt) -> Void
        typealias SetStyle = @convention(c) (id, SEL, Int) -> Void
        unsafeBitCast(ObjC.msgSend, to: SetStyle.self)(made, ObjC.selector("setNumberStyle:"), 1)
        unsafeBitCast(ObjC.msgSend, to: SetInt.self)(made, ObjC.selector("setMaximumFractionDigits:"), 3)
        return made
    }

    /// A number as a formatter writes it, or as one without settings does.
    static func string(_ value: Double, formatter: id?) -> String {
        if let formatter,
           let text = Strings.value(of: ObjC.send(formatter, ObjC.selector("stringFromNumber:"), Numbers.make(nil, .double(value)))) {
            return text
        }
        return format(value)
    }

    /// Whether the locale measures in the imperial system.
    static var imperial: Bool {
        ["US", "LR", "MM"].contains(Locale.current.region?.identifier ?? "")
    }
}

/// NSLengthFormatter: a length as text, "5.2 km".
@ObjCClass("NSLengthFormatter")
public class NSLengthFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: LengthFormatterStorage {
        if let state = Storage.get(objcObject, as: LengthFormatterStorage.self) { return state }
        let state = LengthFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSLengthFormatter.formatterClass)
    }

    @ObjCMethod("unitStyle") func unitStyle() -> Int { state.unitStyle }
    @ObjCMethod("setUnitStyle:") func setUnitStyle(_ style: Int) { state.unitStyle = style }
    @ObjCMethod("isForPersonHeightUse") func isForPersonHeightUse() -> Bool { state.forPersonHeightUse }
    @ObjCMethod("setForPersonHeightUse:") func setForPersonHeightUse(_ use: Bool) { state.forPersonHeightUse = use }

    @ObjCMethod("numberFormatter")
    func numberFormatter() -> UnsafeMutableRawPointer? {
        if state.numberFormatter == nil { state.numberFormatter = Units.makeNumberFormatter() }
        return state.numberFormatter
    }

    @ObjCMethod("setNumberFormatter:")
    func setNumberFormatter(_ formatter: ObjCObject?) {
        if let old = state.numberFormatter { ObjC.release(old) }
        state.numberFormatter = formatter.flatMap { ObjC.retain($0.objcObject) }
    }

    /// NSLengthFormatterUnit: its meters per unit and its short, medium
    /// and long writings.
    private static let units: [Int: (meters: Double, short: String, medium: String, singular: String, plural: String)] = [
        8: (0.001, "mm", "mm", "millimeter", "millimeters"),
        9: (0.01, "cm", "cm", "centimeter", "centimeters"),
        11: (1, "m", "m", "meter", "meters"),
        14: (1000, "km", "km", "kilometer", "kilometers"),
        1281: (0.0254, "″", "in", "inch", "inches"),
        1282: (0.3048, "′", "ft", "foot", "feet"),
        1283: (0.9144, "yd", "yd", "yard", "yards"),
        1284: (1609.344, "mi", "mi", "mile", "miles"),
    ]

    private func name(_ unit: Int, _ value: Double) -> String {
        guard let found = NSLengthFormatter.units[unit] else { return "" }
        switch state.unitStyle {
        case 3: return value == 1 ? found.singular : found.plural
        case 1: return found.short
        default: return found.medium
        }
    }

    @ObjCMethod("stringFromValue:unit:")
    func string(fromValue value: Double, unit: Int) -> String {
        let number = Units.string(value, formatter: numberFormatter())
        let text = name(unit, value)
        return state.unitStyle == 1 && (unit == 1281 || unit == 1282) ? number + text : number + " " + text
    }

    @ObjCMethod("unitStringFromValue:unit:")
    func unitString(fromValue value: Double, unit: Int) -> String { name(unit, value) }

    /// The unit that suits a length in meters, and the length in it.
    private func suited(_ meters: Double) -> (value: Double, unit: Int) {
        let size = abs(meters)
        if !Units.imperial {
            if state.forPersonHeightUse { return (meters * 100, 9) }
            if size >= 1000 { return (meters / 1000, 14) }
            if size >= 1 || size == 0 { return (meters, 11) }
            if size >= 0.01 { return (meters * 100, 9) }
            return (meters * 1000, 8)
        }
        if state.forPersonHeightUse { return (meters / 0.3048, 1282) }
        if size >= 1609.344 * 0.1 { return (meters / 1609.344, 1284) }
        if size >= 0.3048 * 3 { return (meters / 0.9144, 1283) }
        if size >= 0.3048 { return (meters / 0.3048, 1282) }
        return (meters / 0.0254, 1281)
    }

    @ObjCMethod("stringFromMeters:")
    func string(fromMeters meters: Double) -> String {
        let (value, unit) = suited(meters)
        return string(fromValue: value, unit: unit)
    }

    @ObjCMethod("unitStringFromMeters:usedUnit:")
    func unitString(fromMeters meters: Double, usedUnit: UnsafeMutablePointer<Int>?) -> String {
        let (value, unit) = suited(meters)
        usedUnit?.pointee = unit
        return name(unit, value)
    }

    @ObjCMethod("stringForObjectValue:")
    func string(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Numbers.numberClass) else { return nil }
        typealias Fn = @convention(c) (id, SEL) -> Double
        return string(fromMeters: unsafeBitCast(ObjC.msgSend, to: Fn.self)(value.objcObject, ObjC.selector("doubleValue")))
    }
}

// MARK: - NSDateComponentsFormatter

final class DateComponentsFormatterStorage {
    var allowedUnits: UInt = 0
    /// NSDateComponentsFormatterUnitsStyle: positional 0, abbreviated 1,
    /// short 2, full 3, spelled out 4, brief 5.
    var unitsStyle = 0
    var zeroFormattingBehavior: UInt = 0
    var maximumUnitCount = 0
    var collapsesLargestUnit = false
    var includesApproximationPhrase = false
    var includesTimeRemainingPhrase = false
    var allowsFractionalUnits = false
    var formattingContext = 0
    var calendar: id?
    var referenceDate: id?

    deinit {
        if let calendar { ObjC.release(calendar) }
        if let referenceDate { ObjC.release(referenceDate) }
    }
}

/// NSDateComponentsFormatter: a duration as text, "1:02:03" or "1h 2m 3s".
@ObjCClass("NSDateComponentsFormatter")
public class NSDateComponentsFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: DateComponentsFormatterStorage {
        if let state = Storage.get(objcObject, as: DateComponentsFormatterStorage.self) { return state }
        let state = DateComponentsFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSDateComponentsFormatter.formatterClass)
    }

    @ObjCMethod("allowedUnits") func allowedUnits() -> UInt { state.allowedUnits }
    @ObjCMethod("setAllowedUnits:") func setAllowedUnits(_ units: UInt) { state.allowedUnits = units }
    @ObjCMethod("unitsStyle") func unitsStyle() -> Int { state.unitsStyle }
    @ObjCMethod("setUnitsStyle:") func setUnitsStyle(_ style: Int) { state.unitsStyle = style }
    @ObjCMethod("zeroFormattingBehavior") func zeroFormattingBehavior() -> UInt { state.zeroFormattingBehavior }
    @ObjCMethod("setZeroFormattingBehavior:") func setZeroFormattingBehavior(_ behavior: UInt) { state.zeroFormattingBehavior = behavior }
    @ObjCMethod("maximumUnitCount") func maximumUnitCount() -> Int { state.maximumUnitCount }
    @ObjCMethod("setMaximumUnitCount:") func setMaximumUnitCount(_ count: Int) { state.maximumUnitCount = count }
    @ObjCMethod("collapsesLargestUnit") func collapsesLargestUnit() -> Bool { state.collapsesLargestUnit }
    @ObjCMethod("setCollapsesLargestUnit:") func setCollapsesLargestUnit(_ collapses: Bool) { state.collapsesLargestUnit = collapses }
    @ObjCMethod("includesApproximationPhrase") func includesApproximationPhrase() -> Bool { state.includesApproximationPhrase }
    @ObjCMethod("setIncludesApproximationPhrase:") func setIncludesApproximationPhrase(_ includes: Bool) { state.includesApproximationPhrase = includes }
    @ObjCMethod("includesTimeRemainingPhrase") func includesTimeRemainingPhrase() -> Bool { state.includesTimeRemainingPhrase }
    @ObjCMethod("setIncludesTimeRemainingPhrase:") func setIncludesTimeRemainingPhrase(_ includes: Bool) { state.includesTimeRemainingPhrase = includes }
    @ObjCMethod("allowsFractionalUnits") func allowsFractionalUnits() -> Bool { state.allowsFractionalUnits }
    @ObjCMethod("setAllowsFractionalUnits:") func setAllowsFractionalUnits(_ allows: Bool) { state.allowsFractionalUnits = allows }
    @ObjCMethod("formattingContext") func formattingContext() -> Int { state.formattingContext }
    @ObjCMethod("setFormattingContext:") func setFormattingContext(_ context: Int) { state.formattingContext = context }

    @ObjCMethod("calendar") func calendar() -> UnsafeMutableRawPointer? { state.calendar }
    @ObjCMethod("setCalendar:") func setCalendar(_ calendar: ObjCObject?) {
        if let old = state.calendar { ObjC.release(old) }
        state.calendar = calendar.flatMap { ObjC.retain($0.objcObject) }
    }
    @ObjCMethod("referenceDate") func referenceDate() -> UnsafeMutableRawPointer? { state.referenceDate }
    @ObjCMethod("setReferenceDate:") func setReferenceDate(_ date: ObjCObject?) {
        if let old = state.referenceDate { ObjC.release(old) }
        state.referenceDate = date.flatMap { ObjC.retain($0.objcObject) }
    }

    /// NSCalendarUnit, the largest first, with its seconds and its writings.
    private static let units: [(bit: UInt, seconds: Double, abbreviated: String, short: String, brief: String, singular: String, plural: String)] = [
        (4, 365 * 86400, "y", "yr", "yr", "year", "years"),
        (8, 30 * 86400, "mo", "mth", "mth", "month", "months"),
        (4096, 7 * 86400, "w", "wk", "wk", "week", "weeks"),
        (16, 86400, "d", "day", "d", "day", "days"),
        (32, 3600, "h", "hr", "hr", "hour", "hours"),
        (64, 60, "m", "min", "min", "minute", "minutes"),
        (128, 1, "s", "sec", "sec", "second", "seconds"),
    ]

    @ObjCMethod("stringFromTimeInterval:")
    func string(fromTimeInterval interval: Double) -> String? {
        guard interval.isFinite else { return nil }
        var allowed = state.allowedUnits
        if allowed == 0 { allowed = 4 | 8 | 4096 | 16 | 32 | 64 | 128 }
        var remaining = abs(interval).rounded(.towardZero)
        var values: [(unit: Int, count: Int)] = []
        for (index, unit) in NSDateComponentsFormatter.units.enumerated() where allowed & unit.bit != 0 {
            let count = (remaining / unit.seconds).rounded(.towardZero)
            remaining -= count * unit.seconds
            values.append((index, Int(count)))
        }
        guard !values.isEmpty else { return nil }
        let text = write(values)
        return interval < 0 ? "-" + text : text
    }

    private func write(_ all: [(unit: Int, count: Int)]) -> String {
        let behavior = state.zeroFormattingBehavior
        let positional = state.unitsStyle == 0
        var values = all
        // Zero units: positional keeps its units unless told to drop them;
        // the others drop them unless told to keep them.
        let dropLeading = behavior & 1 != 0, dropMiddle = behavior & 2 != 0, dropTrailing = behavior & 4 != 0
        if positional {
            if dropLeading { while values.count > 2, values[0].count == 0 { values.removeFirst() } }
            if dropTrailing { while values.count > 1, values[values.count - 1].count == 0 { values.removeLast() } }
            if dropMiddle { values = values.enumerated().filter { $0.offset == 0 || $0.offset == values.count - 1 || $0.element.count != 0 }.map(\.element) }
        } else {
            values = values.filter { $0.count != 0 }
            if values.isEmpty, let last = all.last { values = [last] }
        }
        // The units counted from the first with a value.
        if state.maximumUnitCount > 0 {
            if let start = values.firstIndex(where: { $0.count != 0 }) { values = Array(values[start...]) }
            values = Array(values.prefix(state.maximumUnitCount))
        }
        let pad = behavior & 0x10000 != 0
        let units = NSDateComponentsFormatter.units
        switch state.unitsStyle {
        case 0:
            var parts: [String] = []
            for (index, value) in values.enumerated() {
                let digits = String(value.count)
                parts.append(index > 0 || pad ? String(repeating: "0", count: max(0, 2 - digits.count)) + digits : digits)
            }
            return parts.joined(separator: ":")
        case 1:
            return values.map { "\($0.count)\(units[$0.unit].abbreviated)" }.joined(separator: " ")
        case 5:
            return values.map { "\($0.count)\(units[$0.unit].brief)" }.joined(separator: " ")
        case 2:
            return values.map { "\($0.count) \(units[$0.unit].short)" }.joined(separator: ", ")
        default:
            return values.map { "\($0.count) \($0.count == 1 ? units[$0.unit].singular : units[$0.unit].plural)" }.joined(separator: ", ")
        }
    }

    /// The date components' units as a duration.
    private static func seconds(of components: id) -> Double? {
        let selectors: [(String, Double)] = [("year", 365 * 86400), ("month", 30 * 86400), ("weekOfMonth", 7 * 86400),
                                             ("day", 86400), ("hour", 3600), ("minute", 60), ("second", 1)]
        var total = 0.0
        var found = false
        for (name, seconds) in selectors {
            typealias Fn = @convention(c) (id, SEL) -> Int
            let value = unsafeBitCast(ObjC.msgSend, to: Fn.self)(components, ObjC.selector(name))
            // NSDateComponentUndefined is NSIntegerMax.
            guard value != Int.max, value != Int(Int32.max) else { continue }
            total += Double(value) * seconds
            found = true
        }
        return found ? total : nil
    }

    @ObjCMethod("stringFromDateComponents:")
    func string(fromDateComponents components: ObjCObject?) -> String? {
        guard let components, let seconds = NSDateComponentsFormatter.seconds(of: components.objcObject) else { return nil }
        return string(fromTimeInterval: seconds)
    }

    @ObjCMethod("stringFromDate:toDate:")
    func string(fromDate start: ObjCObject?, toDate end: ObjCObject?) -> String? {
        guard let start, let end else { return nil }
        return string(fromTimeInterval: Dates.date(end.objcObject).timeIntervalSince(Dates.date(start.objcObject)))
    }

    @ObjCMethod("stringForObjectValue:")
    func string(forObjectValue value: ObjCObject?) -> String? {
        guard let value else { return nil }
        if ObjC.isKind(value.objcObject, of: Numbers.numberClass) {
            typealias Fn = @convention(c) (id, SEL) -> Double
            return string(fromTimeInterval: unsafeBitCast(ObjC.msgSend, to: Fn.self)(value.objcObject, ObjC.selector("doubleValue")))
        }
        return string(fromDateComponents: value)
    }
}
