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
    /// "NSUnitLength.meters" for a class method's shared unit: what
    /// NSMeasurementFormatter knows it by. Units made otherwise have none,
    /// and are written by their symbol, as on Darwin.
    var tableKey: String?
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

final class ReciprocalConverterStorage {
    var reciprocal = 1.0
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
    nonisolated(unsafe) static var reciprocalClass: Class!
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

    static func reciprocal(_ object: id) -> ReciprocalConverterStorage {
        if let storage = Storage.get(object, as: ReciprocalConverterStorage.self) { return storage }
        let storage = ReciprocalConverterStorage()
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

    /// A reciprocal converter: base value = reciprocal ÷ value.
    static func makeReciprocalConverter(_ reciprocal: Double) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(reciprocalClass)) else { return nil }
        Units.reciprocal(object).reciprocal = reciprocal
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

/// NSUnitConverterReciprocal: base value = reciprocal ÷ value, both ways;
/// what NSUnitFuelEfficiency's miles per gallon convert by. Private on
/// Darwin, where it has these methods.
@ObjCClass("NSUnitConverterReciprocal")
public class NSUnitConverterReciprocal: NSUnitConverter {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Units.reciprocalClass = cls.storage
    }

    var state: ReciprocalConverterStorage { Units.reciprocal(objcObject) }

    @ObjCMethod("initWithReciprocalValue:")
    func initialize(reciprocalValue: Double) -> Self {
        state.reciprocal = reciprocalValue
        return self
    }

    @ObjCMethod("reciprocalValue") func reciprocalValue() -> Double { state.reciprocal }

    @ObjCMethod("baseUnitValueFromValue:")
    override func baseUnitValue(fromValue value: Double) -> Double { state.reciprocal / value }

    @ObjCMethod("valueFromBaseUnitValue:")
    override func value(fromBaseUnitValue value: Double) -> Double { state.reciprocal / value }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, ObjC.objectGetClass(other.objcObject) == ObjC.objectGetClass(objcObject) else { return false }
        return Units.reciprocal(other.objcObject).reciprocal == state.reciprocal
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(truncatingIfNeeded: state.reciprocal.bitPattern) }
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

    /// Each quantity's class says its base unit; NSDimension has none, and
    /// raises, as on Darwin.
    @ObjCClassMethod("baseUnit")
    static func baseUnit(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        let name = ObjC.name(ofClass: UnsafeMutableRawPointer(cls.storage))
        Exceptions.raise(name: "NSInvalidArgumentException",
                         reason: "*** You must override baseUnit in your class \(name) to define its base unit.")
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
    /// Whether the coefficient is a reciprocal converter's value instead.
    var reciprocal = false
    var name: (singular: String, plural: String)?

    init(_ selector: String, _ symbol: String, _ coefficient: Double, constant: Double = 0, reciprocal: Bool = false,
         name: (String, String)? = nil) {
        self.selector = selector
        self.symbol = symbol
        self.coefficient = coefficient
        self.constant = constant
        self.reciprocal = reciprocal
        self.name = name.map { (singular: $0.0, plural: $0.1) }
    }
}

enum UnitTables {
    /// The base unit's selector and the units of each class, with Darwin's
    /// symbols and coefficients.
    static let tables: [String: (base: String, units: [UnitSpec])] = [
        "NSUnitLength": ("meters", [
            UnitSpec("megameters", "Mm", 1000000, name: ("megameter", "megameters")),
            UnitSpec("kilometers", "km", 1000, name: ("kilometer", "kilometers")),
            UnitSpec("hectometers", "hm", 100, name: ("hectometer", "hectometers")),
            UnitSpec("decameters", "dam", 10, name: ("decameter", "decameters")),
            UnitSpec("meters", "m", 1, name: ("meter", "meters")),
            UnitSpec("decimeters", "dm", 0.1, name: ("decimeter", "decimeters")),
            UnitSpec("centimeters", "cm", 0.01, name: ("centimeter", "centimeters")),
            UnitSpec("millimeters", "mm", 0.001, name: ("millimeter", "millimeters")),
            UnitSpec("micrometers", "µm", 1e-06, name: ("micrometer", "micrometers")),
            UnitSpec("nanometers", "nm", 1e-09, name: ("nanometer", "nanometers")),
            UnitSpec("picometers", "pm", 1e-12, name: ("picometer", "picometers")),
            UnitSpec("inches", "in", 0.0254, name: ("inch", "inches")),
            UnitSpec("feet", "ft", 0.3048, name: ("foot", "feet")),
            UnitSpec("yards", "yd", 0.9144, name: ("yard", "yards")),
            UnitSpec("miles", "mi", 1609.344, name: ("mile", "miles")),
            UnitSpec("scandinavianMiles", "smi", 10000, name: ("Scandinavian mile", "Scandinavian miles")),
            UnitSpec("lightyears", "ly", 9460730472580800, name: ("light year", "light years")),
            UnitSpec("nauticalMiles", "NM", 1852, name: ("nautical mile", "nautical miles")),
            UnitSpec("fathoms", "ftm", 1.8288, name: ("fathom", "fathoms")),
            UnitSpec("furlongs", "fur", 201.168, name: ("furlong", "furlongs")),
            UnitSpec("astronomicalUnits", "ua", 149597870700, name: ("astronomical unit", "astronomical units")),
            UnitSpec("parsecs", "pc", 3.085677581491367e+16, name: ("parsec", "parsecs")),
        ]),
        "NSUnitSpeed": ("metersPerSecond", [
            UnitSpec("metersPerSecond", "m/s", 1, name: ("meter per second", "meters per second")),
            UnitSpec("kilometersPerHour", "km/h", 0.277778, name: ("kilometer per hour", "kilometers per hour")),
            UnitSpec("milesPerHour", "mph", 0.44704, name: ("mile per hour", "miles per hour")),
            UnitSpec("knots", "kn", 0.514444, name: ("knot", "knots")),
        ]),
        "NSUnitDuration": ("seconds", [
            UnitSpec("seconds", "s", 1, name: ("second", "seconds")),
            UnitSpec("milliseconds", "ms", 0.001, name: ("millisecond", "milliseconds")),
            UnitSpec("microseconds", "µs", 1e-06, name: ("microsecond", "microseconds")),
            UnitSpec("nanoseconds", "ns", 1e-09, name: ("nanosecond", "nanoseconds")),
            UnitSpec("picoseconds", "ps", 1e-12, name: ("picosecond", "picoseconds")),
            UnitSpec("minutes", "min", 60, name: ("minute", "minutes")),
            UnitSpec("hours", "hr", 3600, name: ("hour", "hours")),
        ]),
        "NSUnitMass": ("kilograms", [
            UnitSpec("kilograms", "kg", 1, name: ("kilogram", "kilograms")),
            UnitSpec("grams", "g", 0.001, name: ("gram", "grams")),
            UnitSpec("decigrams", "dg", 0.0001, name: ("decigram", "decigrams")),
            UnitSpec("centigrams", "cg", 1e-05, name: ("centigram", "centigrams")),
            UnitSpec("milligrams", "mg", 1e-06, name: ("milligram", "milligrams")),
            UnitSpec("micrograms", "µg", 1e-09, name: ("microgram", "micrograms")),
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
            UnitSpec("fahrenheit", "°F", 0.55555555555556, constant: 255.37222222222428, name: ("degree Fahrenheit", "degrees Fahrenheit")),
        ]),
        "NSUnitAngle": ("degrees", [
            UnitSpec("degrees", "°", 1, name: ("degree", "degrees")),
            UnitSpec("arcMinutes", "ʹ", 0.016667, name: ("arcminute", "arcminutes")),
            UnitSpec("arcSeconds", "ʺ", 0.00027778, name: ("arcsecond", "arcseconds")),
            UnitSpec("radians", "rad", 57.29577951308232, name: ("radian", "radians")),
            UnitSpec("gradians", "grad", 0.9, name: ("gradian", "gradians")),
            UnitSpec("revolutions", "rev", 360, name: ("revolution", "revolutions")),
        ]),
        "NSUnitPower": ("watts", [
            UnitSpec("terawatts", "TW", 1000000000000, name: ("terawatt", "terawatts")),
            UnitSpec("gigawatts", "GW", 1000000000, name: ("gigawatt", "gigawatts")),
            UnitSpec("megawatts", "MW", 1000000, name: ("megawatt", "megawatts")),
            UnitSpec("kilowatts", "kW", 1000, name: ("kilowatt", "kilowatts")),
            UnitSpec("watts", "W", 1, name: ("watt", "watts")),
            UnitSpec("milliwatts", "mW", 0.001, name: ("milliwatt", "milliwatts")),
            UnitSpec("microwatts", "µW", 1e-06, name: ("microwatt", "microwatts")),
            UnitSpec("nanowatts", "nW", 1e-09, name: ("nanowatt", "nanowatts")),
            UnitSpec("picowatts", "pW", 1e-12, name: ("picowatt", "picowatts")),
            UnitSpec("femtowatts", "fW", 1e-15, name: ("femtowatt", "femtowatts")),
            UnitSpec("horsepower", "hp", 745.7, name: ("horsepower", "horsepower")),
        ]),
        "NSUnitPressure": ("newtonsPerMetersSquared", [
            UnitSpec("newtonsPerMetersSquared", "N/m²", 1, name: ("newton per square meter", "newtons per square meter")),
            UnitSpec("gigapascals", "GPa", 1000000000, name: ("gigapascal", "gigapascals")),
            UnitSpec("megapascals", "MPa", 1000000, name: ("megapascal", "megapascals")),
            UnitSpec("kilopascals", "kPa", 1000, name: ("kilopascal", "kilopascals")),
            UnitSpec("hectopascals", "hPa", 100, name: ("hectopascal", "hectopascals")),
            UnitSpec("inchesOfMercury", "inHg", 3386.39, name: ("inch of mercury", "inches of mercury")),
            UnitSpec("bars", "bar", 100000, name: ("bar", "bars")),
            UnitSpec("millibars", "mbar", 100, name: ("millibar", "millibars")),
            UnitSpec("millimetersOfMercury", "mmHg", 133.322, name: ("millimeter of mercury", "millimeters of mercury")),
            UnitSpec("poundsForcePerSquareInch", "psi", 6894.76, name: ("pound per square inch", "pounds per square inch")),
        ]),
        "NSUnitAcceleration": ("metersPerSecondSquared", [
            UnitSpec("metersPerSecondSquared", "m/s²", 1, name: ("meter per second squared", "meters per second squared")),
            UnitSpec("gravity", "g", 9.81, name: ("g-force", "g-force")),
        ]),
        "NSUnitArea": ("squareMeters", [
            UnitSpec("squareMegameters", "Mm²", 1000000000000, name: ("square megameter", "square megameters")),
            UnitSpec("squareKilometers", "km²", 1000000, name: ("square kilometer", "square kilometers")),
            UnitSpec("squareMeters", "m²", 1, name: ("square meter", "square meters")),
            UnitSpec("squareCentimeters", "cm²", 0.0001, name: ("square centimeter", "square centimeters")),
            UnitSpec("squareMillimeters", "mm²", 1e-06, name: ("square millimeter", "square millimeters")),
            UnitSpec("squareInches", "in²", 0.00064516, name: ("square inch", "square inches")),
            UnitSpec("squareFeet", "ft²", 0.09290304, name: ("square foot", "square feet")),
            UnitSpec("squareYards", "yd²", 0.83612736, name: ("square yard", "square yards")),
            UnitSpec("squareMiles", "mi²", 2589988.110336, name: ("square mile", "square miles")),
            UnitSpec("acres", "ac", 4046.8564224, name: ("acre", "acres")),
            UnitSpec("ares", "a", 100, name: ("are", "ares")),
            UnitSpec("hectares", "ha", 10000, name: ("hectare", "hectares")),
            UnitSpec("squareMicrometers", "µm²", 1e-12),
            UnitSpec("squareNanometers", "nm²", 1e-18),
        ]),
        "NSUnitVolume": ("liters", [
            UnitSpec("megaliters", "ML", 1000000, name: ("megaliter", "megaliters")),
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
            UnitSpec("acreFeet", "af", 1233000, name: ("acre-foot", "acre-feet")),
            UnitSpec("bushels", "bsh", 35.2391, name: ("bushel", "bushels")),
            UnitSpec("cubicDecimeters", "dm³", 1),
            UnitSpec("cubicKilometers", "km³", 1000000000000, name: ("cubic kilometer", "cubic kilometers")),
            UnitSpec("cubicMiles", "mi³", 4168000000000, name: ("cubic mile", "cubic miles")),
            UnitSpec("cubicMillimeters", "mm³", 1e-06),
            UnitSpec("cubicYards", "yd³", 764.555, name: ("cubic yard", "cubic yards")),
            UnitSpec("imperialFluidOunces", "fl oz", 0.0284131),
            UnitSpec("imperialGallons", "gal", 4.54609, name: ("Imp. gallon", "Imp. gallons")),
            UnitSpec("imperialPints", "pt", 0.568261),
            UnitSpec("imperialQuarts", "qt", 1.13652),
            UnitSpec("imperialTablespoons", "tbsp", 0.0177582),
            UnitSpec("imperialTeaspoons", "tsp", 0.00591939),
            UnitSpec("metricCups", "metric cup", 0.25),
        ]),
        "NSUnitConcentrationMass": ("gramsPerLiter", [
            UnitSpec("gramsPerLiter", "g/L", 1, name: ("gram per liter", "grams per liter")),
            UnitSpec("milligramsPerDeciliter", "mg/dL", 0.01, name: ("milligram per deciliter", "milligrams per deciliter")),
        ]),
        "NSUnitElectricPotentialDifference": ("volts", [
            UnitSpec("megavolts", "MV", 1000000, name: ("megavolt", "megavolts")),
            UnitSpec("kilovolts", "kV", 1000, name: ("kilovolt", "kilovolts")),
            UnitSpec("volts", "V", 1, name: ("volt", "volts")),
            UnitSpec("millivolts", "mV", 0.001, name: ("millivolt", "millivolts")),
            UnitSpec("microvolts", "µV", 1e-06, name: ("microvolt", "microvolts")),
        ]),
        "NSUnitFrequency": ("hertz", [
            UnitSpec("terahertz", "THz", 1000000000000, name: ("terahertz", "terahertz")),
            UnitSpec("gigahertz", "GHz", 1000000000, name: ("gigahertz", "gigahertz")),
            UnitSpec("megahertz", "MHz", 1000000, name: ("megahertz", "megahertz")),
            UnitSpec("kilohertz", "kHz", 1000, name: ("kilohertz", "kilohertz")),
            UnitSpec("hertz", "Hz", 1, name: ("hertz", "hertz")),
            UnitSpec("millihertz", "mHz", 0.001, name: ("millihertz", "millihertz")),
            UnitSpec("microhertz", "µHz", 1e-06, name: ("microhertz", "microhertz")),
            UnitSpec("nanohertz", "nHz", 1e-09, name: ("nanohertz", "nanohertz")),
            UnitSpec("framesPerSecond", "fps", 1, name: ("frame per second", "frames per second")),
        ]),
        "NSUnitInformationStorage": ("bytes", [
            UnitSpec("bytes", "B", 1, name: ("byte", "bytes")),
            UnitSpec("bits", "bit", 0.125, name: ("bit", "bits")),
            UnitSpec("nibbles", "nibble", 0.5, name: ("nibble", "nibbles")),
            UnitSpec("kilobytes", "kB", 1000, name: ("kilobyte", "kilobytes")),
            UnitSpec("megabytes", "MB", 1000000, name: ("megabyte", "megabytes")),
            UnitSpec("gigabytes", "GB", 1000000000, name: ("gigabyte", "gigabytes")),
            UnitSpec("terabytes", "TB", 1000000000000, name: ("terabyte", "terabytes")),
            UnitSpec("kibibytes", "KiB", 1024, name: ("kibibyte", "kibibytes")),
            UnitSpec("mebibytes", "MiB", 1048576, name: ("mebibyte", "mebibytes")),
            UnitSpec("gibibytes", "GiB", 1073741824, name: ("gibibyte", "gibibytes")),
            UnitSpec("exabits", "Eb", 1.25e+17),
            UnitSpec("exabytes", "EB", 1e+18),
            UnitSpec("exbibits", "Eib", 1.4411518807585587e+17),
            UnitSpec("exbibytes", "EiB", 1.152921504606847e+18),
            UnitSpec("gibibits", "Gib", 134217728),
            UnitSpec("gigabits", "Gb", 125000000, name: ("gigabit", "gigabits")),
            UnitSpec("kibibits", "Kib", 128),
            UnitSpec("kilobits", "kb", 125, name: ("kilobit", "kilobits")),
            UnitSpec("mebibits", "Mib", 131072),
            UnitSpec("megabits", "Mb", 125000, name: ("megabit", "megabits")),
            UnitSpec("pebibits", "Pib", 140737488355328),
            UnitSpec("pebibytes", "PiB", 1125899906842624),
            UnitSpec("petabits", "Pb", 125000000000000),
            UnitSpec("petabytes", "PB", 1000000000000000, name: ("petabyte", "petabytes")),
            UnitSpec("tebibits", "Tib", 137438953472),
            UnitSpec("tebibytes", "TiB", 1099511627776),
            UnitSpec("terabits", "Tb", 125000000000, name: ("terabit", "terabits")),
            UnitSpec("yobibits", "Yib", 1.5111572745182865e+23),
            UnitSpec("yobibytes", "YiB", 1.2089258196146292e+24),
            UnitSpec("yottabits", "Yb", 1.25e+23),
            UnitSpec("yottabytes", "YB", 1e+24),
            UnitSpec("zebibits", "Zib", 1.4757395258967641e+20),
            UnitSpec("zebibytes", "ZiB", 1.1805916207174113e+21),
            UnitSpec("zettabits", "Zb", 1.25e+20),
            UnitSpec("zettabytes", "ZB", 1e+21),
        ]),
        "NSUnitDispersion": ("partsPerMillion", [
            UnitSpec("partsPerMillion", "ppm", 1, name: ("part per million", "parts per million")),
        ]),
        "NSUnitElectricCharge": ("coulombs", [
            UnitSpec("ampereHours", "Ah", 3600),
            UnitSpec("coulombs", "C", 1),
            UnitSpec("kiloampereHours", "kAh", 3600000),
            UnitSpec("megaampereHours", "MAh", 3600000000),
            UnitSpec("microampereHours", "µAh", 0.0036),
            UnitSpec("milliampereHours", "mAh", 3.6),
        ]),
        "NSUnitElectricCurrent": ("amperes", [
            UnitSpec("amperes", "A", 1, name: ("ampere", "amperes")),
            UnitSpec("kiloamperes", "kA", 1000),
            UnitSpec("megaamperes", "MA", 1000000),
            UnitSpec("microamperes", "µA", 1e-06),
            UnitSpec("milliamperes", "mA", 0.001, name: ("milliampere", "milliamperes")),
        ]),
        "NSUnitElectricResistance": ("ohms", [
            UnitSpec("kiloohms", "kΩ", 1000),
            UnitSpec("megaohms", "MΩ", 1000000),
            UnitSpec("microohms", "µΩ", 1e-06),
            UnitSpec("milliohms", "mΩ", 0.001),
            UnitSpec("ohms", "Ω", 1, name: ("ohm", "ohms")),
        ]),
        "NSUnitFuelEfficiency": ("litersPer100Kilometers", [
            UnitSpec("litersPer100Kilometers", "L/100km", 1, name: ("liter per 100 kilometers", "liters per 100 kilometers")),
            UnitSpec("milesPerGallon", "mpg", 235.215, reciprocal: true, name: ("mile per gallon", "miles per gallon")),
            UnitSpec("milesPerImperialGallon", "mpg", 282.481, reciprocal: true, name: ("mile per Imp. gallon", "miles per Imp. gallon")),
        ]),
        "NSUnitIlluminance": ("lux", [
            UnitSpec("lux", "lx", 1, name: ("lux", "lux")),
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
                  let converter = spec.reciprocal ? Units.makeReciprocalConverter(spec.coefficient)
                                                  : Units.makeConverter(coefficient: spec.coefficient, constant: spec.constant) else { return nil }
            let state = Units.storage(object)
            state.symbol = spec.symbol
            state.converter = converter
            state.tableKey = key
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

    /// Millimoles per liter of a substance of the molar mass given: a new
    /// unit each time, "mmol/L", whose grams per liter are the molar mass
    /// ÷ 1000, as on Darwin.
    @ObjCClassMethod("millimolesPerLiterWithGramsPerMole:")
    static func millimolesPerLiter(_ cls: ObjCClass, gramsPerMole: Double) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(cls.storage)) else { return nil }
        let state = Units.storage(object)
        state.symbol = "mmol/L"
        state.converter = Units.makeConverter(coefficient: gramsPerMole / 1000, constant: 0)
        return ObjC.autorelease(object)
    }
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
@ObjCClass("NSUnitDispersion") public class NSUnitDispersion: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitDispersion") }
}
@ObjCClass("NSUnitElectricCharge") public class NSUnitElectricCharge: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitElectricCharge") }
}
@ObjCClass("NSUnitElectricCurrent") public class NSUnitElectricCurrent: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitElectricCurrent") }
}
@ObjCClass("NSUnitElectricResistance") public class NSUnitElectricResistance: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitElectricResistance") }
}
/// Miles per gallon convert reciprocally, by NSUnitConverterReciprocal.
@ObjCClass("NSUnitFuelEfficiency") public class NSUnitFuelEfficiency: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitFuelEfficiency") }
}
@ObjCClass("NSUnitIlluminance") public class NSUnitIlluminance: NSDimension {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { UnitTables.install(cls, "NSUnitIlluminance") }
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
        _ = perryWithVaList([maximumFractionDigits, abs(value)]) { vsnprintf(&buffer, buffer.count, "%.*f", $0) }
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

    /// NSFormattingUnitStyle as an index into the writings: short 0,
    /// medium 1, long 2.
    private var styleIndex: Int { state.unitStyle == 1 ? 0 : state.unitStyle == 3 ? 2 : 1 }

    /// A unit as the style writes it: its name, or its symbol for a unit
    /// Darwin has no name for, or one not made by its class's method.
    @ObjCMethod("stringFromUnit:")
    func string(fromUnit unit: ObjCObject) -> String {
        guard let writing = MeasurementWritings.writing(of: unit.objcObject) else { return Units.symbol(of: unit.objcObject) }
        return writing[styleIndex * 3]
    }

    /// The value written by the number formatter, then the unit as the
    /// style writes it, singular for one ("1 meter", "2.5 meters"); a unit
    /// without a writing as "value symbol". The unit is the one given, as
    /// NSMeasurementFormatterUnitOptionsProvidedUnit has it: the locale's
    /// preferred units and natural scale are not chosen here.
    @ObjCMethod("stringFromMeasurement:")
    func string(fromMeasurement measurement: ObjCObject) -> String {
        let data = Units.measurement(measurement.objcObject)
        guard var unit = data.unit else { return Units.string(data.value, formatter: numberFormatter()) }
        var value = data.value
        // A few units Darwin writes in another of their class's units.
        if let key = Storage.get(unit, as: UnitStorage.self)?.tableKey, let other = MeasurementWritings.writtenAs(key) {
            value = Units.value(fromBase: Units.baseValue(value, of: unit), in: other)
            unit = other
        }
        let number = Units.string(value, formatter: numberFormatter())
        // Temperatures can go without their unit.
        if state.unitOptions & 4 != 0, let temperature = Units.named("NSUnitTemperature"), ObjC.isKind(unit, of: temperature) {
            return number + "°"
        }
        guard let writing = MeasurementWritings.writing(of: unit) else { return number + " " + Units.symbol(of: unit) }
        let pattern = writing[styleIndex * 3 + (number == "1" ? 1 : 2)]
        return pattern.replacingOccurrences(of: "{0}", with: number)
    }

    @ObjCMethod("stringForObjectValue:")
    func string(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Units.measurementClass) else { return nil }
        return string(fromMeasurement: value)
    }
}

/// How NSMeasurementFormatter writes the units Darwin has names for, in
/// English, as Darwin's (ICU's) data has them: by the unit's class and
/// selector, the short, medium and long styles' unit name and patterns for
/// one and for other counts, "|"-separated.
enum MeasurementWritings {
    static let table: [String: String] = [
        "NSUnitDispersion.partsPerMillion": "ppm|{0}ppm|{0}ppm|parts/million|{0} ppm|{0} ppm|parts per million|{0} part per million|{0} parts per million",
        "NSUnitElectricCurrent.amperes": "amp|{0}A|{0}A|amps|{0} A|{0} A|amperes|{0} ampere|{0} amperes",
        "NSUnitElectricCurrent.milliamperes": "mA|{0}mA|{0}mA|milliamps|{0} mA|{0} mA|milliamperes|{0} milliampere|{0} milliamperes",
        "NSUnitElectricResistance.ohms": "ohm|{0}Ω|{0}Ω|ohms|{0} Ω|{0} Ω|ohms|{0} ohm|{0} ohms",
        "NSUnitFuelEfficiency.litersPer100Kilometers": "L/100km|{0}L/100km|{0}L/100km|L/100 km|{0} L/100 km|{0} L/100 km|liters per 100 kilometers|{0} liter per 100 kilometers|{0} liters per 100 kilometers",
        "NSUnitFuelEfficiency.milesPerGallon": "mpg|{0}mpg|{0}mpg|miles/gal|{0} mpg|{0} mpg|miles per gallon|{0} mile per gallon|{0} miles per gallon",
        "NSUnitFuelEfficiency.milesPerImperialGallon": "mpg UK|{0}m/gUK|{0}m/gUK|miles/gal Imp.|{0} mpg Imp.|{0} mpg Imp.|miles per Imp. gallon|{0} mile per Imp. gallon|{0} miles per Imp. gallon",
        "NSUnitIlluminance.lux": "lux|{0}lx|{0}lx|lux|{0} lx|{0} lx|lux|{0} lux|{0} lux",
        "NSUnitInformationStorage.bits": "bit|{0}bit|{0}bit|bit|{0} bit|{0} bit|bits|{0} bit|{0} bits",
        "NSUnitInformationStorage.bytes": "byte|{0}B|{0}B|byte|{0} byte|{0} byte|bytes|{0} byte|{0} bytes",
        "NSUnitInformationStorage.gigabits": "Gbit|{0}Gb|{0}Gb|Gbit|{0} Gb|{0} Gb|gigabits|{0} gigabit|{0} gigabits",
        "NSUnitInformationStorage.gigabytes": "GB|{0}GB|{0}GB|GByte|{0} GB|{0} GB|gigabytes|{0} gigabyte|{0} gigabytes",
        "NSUnitInformationStorage.kilobits": "kbit|{0}kb|{0}kb|kbit|{0} kb|{0} kb|kilobits|{0} kilobit|{0} kilobits",
        "NSUnitInformationStorage.kilobytes": "kB|{0}kB|{0}kB|kByte|{0} kB|{0} kB|kilobytes|{0} kilobyte|{0} kilobytes",
        "NSUnitInformationStorage.megabits": "Mbit|{0}Mb|{0}Mb|Mbit|{0} Mb|{0} Mb|megabits|{0} megabit|{0} megabits",
        "NSUnitInformationStorage.megabytes": "MB|{0}MB|{0}MB|MByte|{0} MB|{0} MB|megabytes|{0} megabyte|{0} megabytes",
        "NSUnitInformationStorage.petabytes": "PB|{0}PB|{0}PB|PByte|{0} PB|{0} PB|petabytes|{0} petabyte|{0} petabytes",
        "NSUnitInformationStorage.terabits": "Tbit|{0}Tb|{0}Tb|Tbit|{0} Tb|{0} Tb|terabits|{0} terabit|{0} terabits",
        "NSUnitInformationStorage.terabytes": "TB|{0}TB|{0}TB|TByte|{0} TB|{0} TB|terabytes|{0} terabyte|{0} terabytes",
        "NSUnitVolume.acreFeet": "acre ft|{0}ac ft|{0}ac ft|acre ft|{0} ac ft|{0} ac ft|acre-feet|{0} acre-foot|{0} acre-feet",
        "NSUnitVolume.bushels": "bushel|{0}bu|{0}bu|bushels|{0} bu|{0} bu|bushels|{0} bushel|{0} bushels",
        "NSUnitVolume.centiliters": "cL|{0}cL|{0}cL|cL|{0} cL|{0} cL|centiliters|{0} centiliter|{0} centiliters",
        "NSUnitVolume.cubicCentimeters": "cm³|{0}cm³|{0}cm³|cm³|{0} cm³|{0} cm³|cubic centimeters|{0} cubic centimeter|{0} cubic centimeters",
        "NSUnitVolume.cubicFeet": "ft³|{0}ft³|{0}ft³|feet³|{0} ft³|{0} ft³|cubic feet|{0} cubic foot|{0} cubic feet",
        "NSUnitVolume.cubicInches": "in³|{0}in³|{0}in³|inches³|{0} in³|{0} in³|cubic inches|{0} cubic inch|{0} cubic inches",
        "NSUnitVolume.cubicKilometers": "km³|{0}km³|{0}km³|km³|{0} km³|{0} km³|cubic kilometers|{0} cubic kilometer|{0} cubic kilometers",
        "NSUnitVolume.cubicMeters": "m³|{0}m³|{0}m³|m³|{0} m³|{0} m³|cubic meters|{0} cubic meter|{0} cubic meters",
        "NSUnitVolume.cubicMiles": "mi³|{0}mi³|{0}mi³|mi³|{0} mi³|{0} mi³|cubic miles|{0} cubic mile|{0} cubic miles",
        "NSUnitVolume.cubicYards": "yd³|{0}yd³|{0}yd³|yards³|{0} yd³|{0} yd³|cubic yards|{0} cubic yard|{0} cubic yards",
        "NSUnitVolume.cups": "cup|{0}c|{0}c|cups|{0} c|{0} c|cups|{0} cup|{0} cups",
        "NSUnitVolume.deciliters": "dL|{0}dL|{0}dL|dL|{0} dL|{0} dL|deciliters|{0} deciliter|{0} deciliters",
        "NSUnitVolume.fluidOunces": "fl oz|{0}fl oz|{0}fl oz|fl oz|{0} fl oz|{0} fl oz|fluid ounces|{0} fluid ounce|{0} fluid ounces",
        "NSUnitVolume.gallons": "gal|{0}gal|{0}gal|gal|{0} gal|{0} gal|gallons|{0} gallon|{0} gallons",
        "NSUnitVolume.imperialFluidOunces": "fl oz|{0}fl oz|{0}fl oz|fl oz|{0} fl oz|{0} fl oz|fluid ounces|{0} fluid ounce|{0} fluid ounces",
        "NSUnitVolume.imperialGallons": "Imp gal|{0}gal-Im|{0}gal-Im|Imp. gal|{0} gal Imp.|{0} gal Imp.|Imp. gallons|{0} Imp. gallon|{0} Imp. gallons",
        "NSUnitVolume.imperialPints": "pt|{0}pt|{0}pt|pints|{0} pt|{0} pt|pints|{0} pint|{0} pints",
        "NSUnitVolume.imperialQuarts": "qt|{0}qt|{0}qt|qts|{0} qt|{0} qt|quarts|{0} quart|{0} quarts",
        "NSUnitVolume.imperialTablespoons": "tbsp|{0}tbsp|{0}tbsp|tbsp|{0} tbsp|{0} tbsp|tablespoons|{0} tablespoon|{0} tablespoons",
        "NSUnitVolume.imperialTeaspoons": "tsp|{0}tsp|{0}tsp|tsp|{0} tsp|{0} tsp|teaspoons|{0} teaspoon|{0} teaspoons",
        "NSUnitVolume.liters": "liter|{0}L|{0}L|liters|{0} L|{0} L|liters|{0} liter|{0} liters",
        "NSUnitVolume.megaliters": "ML|{0}ML|{0}ML|ML|{0} ML|{0} ML|megaliters|{0} megaliter|{0} megaliters",
        "NSUnitVolume.metricCups": "mcup|{0}mc|{0}mc|mcup|{0} mc|{0} mc|metric cups|{0} metric cup|{0} metric cups",
        "NSUnitVolume.milliliters": "mL|{0}mL|{0}mL|mL|{0} mL|{0} mL|milliliters|{0} milliliter|{0} milliliters",
        "NSUnitVolume.pints": "pt|{0}pt|{0}pt|pints|{0} pt|{0} pt|pints|{0} pint|{0} pints",
        "NSUnitVolume.quarts": "qt|{0}qt|{0}qt|qts|{0} qt|{0} qt|quarts|{0} quart|{0} quarts",
        "NSUnitVolume.tablespoons": "tbsp|{0}tbsp|{0}tbsp|tbsp|{0} tbsp|{0} tbsp|tablespoons|{0} tablespoon|{0} tablespoons",
        "NSUnitVolume.teaspoons": "tsp|{0}tsp|{0}tsp|tsp|{0} tsp|{0} tsp|teaspoons|{0} teaspoon|{0} teaspoons",
        "NSUnitArea.acres": "acre|{0}ac|{0}ac|acres|{0} ac|{0} ac|acres|{0} acre|{0} acres",
        "NSUnitArea.hectares": "hectare|{0}ha|{0}ha|hectares|{0} ha|{0} ha|hectares|{0} hectare|{0} hectares",
        "NSUnitArea.squareCentimeters": "cm²|{0}cm²|{0}cm²|cm²|{0} cm²|{0} cm²|square centimeters|{0} square centimeter|{0} square centimeters",
        "NSUnitArea.squareFeet": "ft²|{0}ft²|{0}ft²|sq feet|{0} sq ft|{0} sq ft|square feet|{0} square foot|{0} square feet",
        "NSUnitArea.squareInches": "in²|{0}in²|{0}in²|inches²|{0} in²|{0} in²|square inches|{0} square inch|{0} square inches",
        "NSUnitArea.squareKilometers": "km²|{0}km²|{0}km²|km²|{0} km²|{0} km²|square kilometers|{0} square kilometer|{0} square kilometers",
        "NSUnitArea.squareMeters": "meters²|{0}m²|{0}m²|meters²|{0} m²|{0} m²|square meters|{0} square meter|{0} square meters",
        "NSUnitArea.squareMiles": "mi²|{0}mi²|{0}mi²|sq miles|{0} sq mi|{0} sq mi|square miles|{0} square mile|{0} square miles",
        "NSUnitArea.squareYards": "yd²|{0}yd²|{0}yd²|yards²|{0} yd²|{0} yd²|square yards|{0} square yard|{0} square yards",
        "NSUnitConcentrationMass.milligramsPerDeciliter": "mg/dL|{0} g/L|{0} g/L|mg/dL|{0} g/L|{0} g/L|milligrams per deciliter|{0} g/L|{0} g/L",
        "NSUnitEnergy.calories": "cal|{0}cal|{0}cal|cal|{0} cal|{0} cal|calories|{0} calorie|{0} calories",
        "NSUnitEnergy.joules": "joule|{0}J|{0}J|joules|{0} J|{0} J|joules|{0} joule|{0} joules",
        "NSUnitEnergy.kilocalories": "kcal|{0}kcal|{0}kcal|kcal|{0} kcal|{0} kcal|kilocalories|{0} kilocalorie|{0} kilocalories",
        "NSUnitEnergy.kilojoules": "kJ|{0}kJ|{0}kJ|kilojoule|{0} kJ|{0} kJ|kilojoules|{0} kilojoule|{0} kilojoules",
        "NSUnitEnergy.kilowattHours": "kWh|{0}kWh|{0}kWh|kW-hour|{0} kWh|{0} kWh|kilowatt-hours|{0} kilowatt hour|{0} kilowatt-hours",
        "NSUnitLength.astronomicalUnits": "au|{0}au|{0}au|au|{0} au|{0} au|astronomical units|{0} astronomical unit|{0} astronomical units",
        "NSUnitLength.centimeters": "cm|{0}cm|{0}cm|cm|{0} cm|{0} cm|centimeters|{0} centimeter|{0} centimeters",
        "NSUnitLength.decimeters": "dm|{0}dm|{0}dm|dm|{0} dm|{0} dm|decimeters|{0} decimeter|{0} decimeters",
        "NSUnitLength.fathoms": "fathom|{0}fth|{0}fth|fathoms|{0} fth|{0} fth|fathoms|{0} fathom|{0} fathoms",
        "NSUnitLength.feet": "ft|{0}′|{0}′|feet|{0} ft|{0} ft|feet|{0} foot|{0} feet",
        "NSUnitLength.furlongs": "furlong|{0}fur|{0}fur|furlongs|{0} fur|{0} fur|furlongs|{0} furlong|{0} furlongs",
        "NSUnitLength.inches": "in|{0}″|{0}″|inches|{0} in|{0} in|inches|{0} inch|{0} inches",
        "NSUnitLength.kilometers": "km|{0}km|{0}km|km|{0} km|{0} km|kilometers|{0} kilometer|{0} kilometers",
        "NSUnitLength.lightyears": "ly|{0}ly|{0}ly|light yrs|{0} ly|{0} ly|light years|{0} light year|{0} light years",
        "NSUnitLength.meters": "meter|{0}m|{0}m|meters|{0} m|{0} m|meters|{0} meter|{0} meters",
        "NSUnitLength.micrometers": "μm|{0}μm|{0}μm|μmeters|{0} μm|{0} μm|micrometers|{0} micrometer|{0} micrometers",
        "NSUnitLength.miles": "mi|{0}mi|{0}mi|miles|{0} mi|{0} mi|miles|{0} mile|{0} miles",
        "NSUnitLength.millimeters": "mm|{0}mm|{0}mm|mm|{0} mm|{0} mm|millimeters|{0} millimeter|{0} millimeters",
        "NSUnitLength.nanometers": "nm|{0}nm|{0}nm|nm|{0} nm|{0} nm|nanometers|{0} nanometer|{0} nanometers",
        "NSUnitLength.nauticalMiles": "nmi|{0}nmi|{0}nmi|nmi|{0} nmi|{0} nmi|nautical miles|{0} nautical mile|{0} nautical miles",
        "NSUnitLength.parsecs": "parsec|{0}pc|{0}pc|parsecs|{0} pc|{0} pc|parsecs|{0} parsec|{0} parsecs",
        "NSUnitLength.picometers": "pm|{0}pm|{0}pm|pm|{0} pm|{0} pm|picometers|{0} picometer|{0} picometers",
        "NSUnitLength.scandinavianMiles": "smi|{0}smi|{0}smi|smi|{0} smi|{0} smi|miles-scandinavian|{0} mile-scandinavian|{0} miles-scandinavian",
        "NSUnitLength.yards": "yd|{0}yd|{0}yd|yards|{0} yd|{0} yd|yards|{0} yard|{0} yards",
        "NSUnitAngle.arcMinutes": "arcmin|{0}′|{0}′|arcmins|{0} arcmin|{0} arcmins|arcminutes|{0} arcminute|{0} arcminutes",
        "NSUnitAngle.arcSeconds": "arcsec|{0}″|{0}″|arcsecs|{0} arcsec|{0} arcsecs|arcseconds|{0} arcsecond|{0} arcseconds",
        "NSUnitAngle.degrees": "deg|{0}°|{0}°|degrees|{0} deg|{0} deg|degrees|{0} degree|{0} degrees",
        "NSUnitAngle.radians": "rad|{0}rad|{0}rad|radians|{0} rad|{0} rad|radians|{0} radian|{0} radians",
        "NSUnitAngle.revolutions": "rev|{0}rev|{0}rev|rev|{0} rev|{0} rev|revolutions|{0} revolution|{0} revolutions",
        "NSUnitTemperature.celsius": "°C|{0}°C|{0}°C|deg. C|{0}°C|{0}°C|degrees Celsius|{0} degree Celsius|{0} degrees Celsius",
        "NSUnitTemperature.fahrenheit": "°F|{0}°|{0}°|deg. F|{0}°F|{0}°F|degrees Fahrenheit|{0} degree Fahrenheit|{0} degrees Fahrenheit",
        "NSUnitTemperature.kelvin": "K|{0}K|{0}K|K|{0} K|{0} K|kelvins|{0} kelvin|{0} kelvins",
        "NSUnitMass.carats": "carat|{0}CD|{0}CD|carats|{0} CD|{0} CD|carats|{0} carat|{0} carats",
        "NSUnitMass.grams": "gram|{0}g|{0}g|grams|{0} g|{0} g|grams|{0} gram|{0} grams",
        "NSUnitMass.kilograms": "kg|{0}kg|{0}kg|kg|{0} kg|{0} kg|kilograms|{0} kilogram|{0} kilograms",
        "NSUnitMass.metricTons": "t|{0}t|{0}t|t|{0} t|{0} t|metric tons|{0} metric ton|{0} metric tons",
        "NSUnitMass.micrograms": "μg|{0}μg|{0}μg|μg|{0} μg|{0} μg|micrograms|{0} microgram|{0} micrograms",
        "NSUnitMass.milligrams": "mg|{0}mg|{0}mg|mg|{0} mg|{0} mg|milligrams|{0} milligram|{0} milligrams",
        "NSUnitMass.ounces": "oz|{0}oz|{0}oz|oz|{0} oz|{0} oz|ounces|{0} ounce|{0} ounces",
        "NSUnitMass.ouncesTroy": "oz t|{0}oz t|{0}oz t|oz troy|{0} oz t|{0} oz t|troy ounces|{0} troy ounce|{0} troy ounces",
        "NSUnitMass.poundsMass": "lb|{0}#|{0}#|pounds|{0} lb|{0} lb|pounds|{0} pound|{0} pounds",
        "NSUnitMass.shortTons": "ton|{0}tn|{0}tn|tons|{0} tn|{0} tn|tons|{0} ton|{0} tons",
        "NSUnitMass.stones": "stone|{0}st|{0}st|stones|{0} st|{0} st|stones|{0} stone|{0} stones",
        "NSUnitSpeed.kilometersPerHour": "km/hr|{0}km/h|{0}km/h|km/hour|{0} km/h|{0} km/h|kilometers per hour|{0} kilometer per hour|{0} kilometers per hour",
        "NSUnitSpeed.knots": "kn|{0}kn|{0}kn|kn|{0} kn|{0} kn|knots|{0} knot|{0} knots",
        "NSUnitSpeed.metersPerSecond": "m/s|{0}m/s|{0}m/s|meters/sec|{0} m/s|{0} m/s|meters per second|{0} meter per second|{0} meters per second",
        "NSUnitSpeed.milesPerHour": "mi/hr|{0}mph|{0}mph|miles/hour|{0} mph|{0} mph|miles per hour|{0} mile per hour|{0} miles per hour",
        "NSUnitDuration.hours": "hour|{0}h|{0}h|hours|{0} hr|{0} hr|hours|{0} hour|{0} hours",
        "NSUnitDuration.microseconds": "μsec|{0}μs|{0}μs|μsecs|{0} μs|{0} μs|microseconds|{0} microsecond|{0} microseconds",
        "NSUnitDuration.milliseconds": "msec|{0}ms|{0}ms|millisecs|{0} ms|{0} ms|milliseconds|{0} millisecond|{0} milliseconds",
        "NSUnitDuration.minutes": "min|{0}m|{0}m|min|{0} min|{0} min|minutes|{0} minute|{0} minutes",
        "NSUnitDuration.nanoseconds": "ns|{0}ns|{0}ns|nanosecs|{0} ns|{0} ns|nanoseconds|{0} nanosecond|{0} nanoseconds",
        "NSUnitDuration.seconds": "sec|{0}s|{0}s|secs|{0} sec|{0} sec|seconds|{0} second|{0} seconds",
        "NSUnitPower.gigawatts": "GW|{0}GW|{0}GW|GW|{0} GW|{0} GW|gigawatts|{0} gigawatt|{0} gigawatts",
        "NSUnitPower.horsepower": "hp|{0}hp|{0}hp|hp|{0} hp|{0} hp|horsepower|{0} horsepower|{0} horsepower",
        "NSUnitPower.kilowatts": "kW|{0}kW|{0}kW|kW|{0} kW|{0} kW|kilowatts|{0} kilowatt|{0} kilowatts",
        "NSUnitPower.megawatts": "MW|{0}MW|{0}MW|MW|{0} MW|{0} MW|megawatts|{0} megawatt|{0} megawatts",
        "NSUnitPower.milliwatts": "mW|{0}mW|{0}mW|mW|{0} mW|{0} mW|milliwatts|{0} milliwatt|{0} milliwatts",
        "NSUnitPower.watts": "watt|{0}W|{0}W|watts|{0} W|{0} W|watts|{0} watt|{0} watts",
        "NSUnitPressure.bars": "bar|{0}bar|{0}bar|bar|{0} bar|{0} bar|bars|{0} bar|{0} bars",
        "NSUnitPressure.hectopascals": "hPa|{0}hPa|{0}hPa|hPa|{0} hPa|{0} hPa|hectopascals|{0} hectopascal|{0} hectopascals",
        "NSUnitPressure.inchesOfMercury": "″ Hg|{0}″ Hg|{0}″ Hg|in Hg|{0} inHg|{0} inHg|inches of mercury|{0} inch of mercury|{0} inches of mercury",
        "NSUnitPressure.kilopascals": "kPa|{0}kPa|{0}kPa|kPa|{0} kPa|{0} kPa|kilopascals|{0} kilopascal|{0} kilopascals",
        "NSUnitPressure.megapascals": "MPa|{0}MPa|{0}MPa|MPa|{0} MPa|{0} MPa|megapascals|{0} megapascal|{0} megapascals",
        "NSUnitPressure.millibars": "mbar|{0}mb|{0}mb|mbar|{0} mbar|{0} mbar|millibars|{0} millibar|{0} millibars",
        "NSUnitPressure.millimetersOfMercury": "mm Hg|{0}mmHg|{0}mmHg|mm Hg|{0} mmHg|{0} mmHg|millimeters of mercury|{0} millimeter of mercury|{0} millimeters of mercury",
        "NSUnitPressure.poundsForcePerSquareInch": "psi|{0}psi|{0}psi|psi|{0} psi|{0} psi|pounds-force per square inch|{0} pound-force per square inch|{0} pounds-force per square inch",
        "NSUnitAcceleration.gravity": "g-force|{0}G|{0}Gs|g-force|{0} G|{0} G|g-force|{0} g-force|{0} g-force",
        "NSUnitAcceleration.metersPerSecondSquared": "m/s²|{0}m/s²|{0}m/s²|meters/sec²|{0} m/s²|{0} m/s²|meters per second squared|{0} meter per second squared|{0} meters per second squared",
        "NSUnitFrequency.gigahertz": "GHz|{0}GHz|{0}GHz|GHz|{0} GHz|{0} GHz|gigahertz|{0} gigahertz|{0} gigahertz",
        "NSUnitFrequency.hertz": "Hz|{0}Hz|{0}Hz|Hz|{0} Hz|{0} Hz|hertz|{0} hertz|{0} hertz",
        "NSUnitFrequency.kilohertz": "kHz|{0}kHz|{0}kHz|kHz|{0} kHz|{0} kHz|kilohertz|{0} kilohertz|{0} kilohertz",
        "NSUnitFrequency.megahertz": "MHz|{0}MHz|{0}MHz|MHz|{0} MHz|{0} MHz|megahertz|{0} megahertz|{0} megahertz",
        "NSUnitElectricPotentialDifference.volts": "volt|{0}V|{0}V|volts|{0} V|{0} V|volts|{0} volt|{0} volts",
    ]

    /// Units Darwin writes as another unit of their class, converted:
    /// imperial cooking measures as US ones, milligrams per deciliter as
    /// grams per liter.
    static let writtenAsSelectors: [String: String] = [
        "NSUnitVolume.imperialFluidOunces": "fluidOunces", "NSUnitVolume.imperialPints": "pints",
        "NSUnitVolume.imperialQuarts": "quarts", "NSUnitVolume.imperialTablespoons": "tablespoons",
        "NSUnitVolume.imperialTeaspoons": "teaspoons", "NSUnitConcentrationMass.milligramsPerDeciliter": "gramsPerLiter",
    ]

    nonisolated(unsafe) private static var parsed: [String: [String]] = [:]
    private static let lock = UnitLock()

    /// The nine writings of a unit its class's method made, if Darwin has
    /// any.
    static func writing(of unit: id) -> [String]? {
        guard let key = Storage.get(unit, as: UnitStorage.self)?.tableKey, let row = table[key] else { return nil }
        return lock.withLock {
            if let found = parsed[key] { return found }
            let fields = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 9 else { return nil }
            parsed[key] = fields
            return fields
        }
    }

    /// The shared unit a unit is written as, by its table key.
    static func writtenAs(_ key: String) -> id? {
        guard let selector = writtenAsSelectors[key], let className = key.split(separator: ".").first.map(String.init),
              let cls = UnitTables.classes[className] else { return nil }
        return ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector(selector))
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

    /// Lengths aren't parsed, on Darwin either: NO, with no value and no
    /// error.
    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        value?.pointee = nil
        errorDescription?.pointee = nil
        return false
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
        // Zero units: positional keeps its units unless told to drop them,
        // and by default drops the leading ones ("1:00:10"); the others
        // drop them unless told to keep them.
        let dropLeading = behavior & 1 != 0 || (positional && behavior == 0)
        let dropMiddle = behavior & 2 != 0, dropTrailing = behavior & 4 != 0
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
        case 4:
            // Spelled out: "one hour, two minutes".
            let speller = NumberFormatterStorage()
            speller.locale = Locale(identifier: "en_US")
            speller.setStyle(5)
            return values.map { value -> String in
                let count = speller.string(fromDouble: Double(value.count))
                return "\(count) \(value.count == 1 ? units[value.unit].singular : units[value.unit].plural)"
            }.joined(separator: ", ")
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

    /// A formatter with the style, writing the components.
    @ObjCClassMethod("localizedStringFromDateComponents:unitsStyle:")
    static func localizedString(_ cls: ObjCClass, from components: ObjCObject?, unitsStyle: Int) -> String? {
        guard let components,
              let formatter = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls.storage), ObjC.selector("alloc")), ObjC.selector("init")) else { return nil }
        defer { ObjC.release(formatter) }
        typealias SetStyle = @convention(c) (id, SEL, Int) -> Void
        unsafeBitCast(ObjC.msgSend, to: SetStyle.self)(formatter, ObjC.selector("setUnitsStyle:"), unitsStyle)
        return Strings.value(of: ObjC.send(formatter, ObjC.selector("stringFromDateComponents:"), components.objcObject))
    }

    /// Durations aren't parsed, on Darwin either: NO, with no value and no
    /// error.
    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        value?.pointee = nil
        errorDescription?.pointee = nil
        return false
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
