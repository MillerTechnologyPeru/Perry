// Measurement: a number of a unit, which Swift's Foundation keeps in the
// framework and apps bind to by its symbols. Units and converters are the
// Objective-C classes NSUnit, NSDimension and NSUnitConverter; a
// Measurement bridges to NSMeasurement.

public struct Measurement<UnitType: Unit>: ReferenceConvertible, Comparable, Equatable {
    public typealias ReferenceType = NSMeasurement

    public let unit: UnitType
    public var value: Double

    public init(value: Double, unit: UnitType) {
        self.value = value
        self.unit = unit
    }

    public var description: String { "\(value) \(unit.symbol)" }
    public var debugDescription: String { "\(value) \(unit.symbol)" }

    /// The value in the base unit of its dimension; the value itself of a
    /// unit with no dimension.
    fileprivate var baseValue: Double {
        guard let dimension = unit as? Dimension else { return value }
        return dimension.converter.baseUnitValue(fromValue: value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(baseValue)
        if !(unit is Dimension) { hasher.combine(unit) }
    }

    public static func == (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Bool {
        if lhs.unit == rhs.unit { return lhs.value == rhs.value }
        guard let left = lhs.unit as? Dimension, let right = rhs.unit as? Dimension,
              type(of: left).baseUnit() == type(of: right).baseUnit() else { return false }
        return lhs.baseValue == rhs.baseValue
    }

    public static func < (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Bool {
        if lhs.unit == rhs.unit { return lhs.value < rhs.value }
        guard lhs.unit is Dimension, rhs.unit is Dimension else {
            fatalError("Attempt to compare measurements with non-equal dimensions")
        }
        return lhs.baseValue < rhs.baseValue
    }

    public static func + (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        combine(lhs, rhs, +)
    }

    public static func - (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        combine(lhs, rhs, -)
    }

    /// The sum or difference: in the unit when both have it, else in the
    /// base unit of their dimension.
    private static func combine(_ lhs: Measurement<UnitType>, _ rhs: Measurement<UnitType>,
                                _ operation: (Double, Double) -> Double) -> Measurement<UnitType> {
        if lhs.unit == rhs.unit { return Measurement(value: operation(lhs.value, rhs.value), unit: lhs.unit) }
        guard let left = lhs.unit as? Dimension, rhs.unit is Dimension,
              let base = type(of: left).baseUnit() as? UnitType else {
            fatalError("Attempt to add measurements with non-equal dimensions")
        }
        return Measurement(value: operation(lhs.baseValue, rhs.baseValue), unit: base)
    }

    public static func * (lhs: Measurement<UnitType>, rhs: Double) -> Measurement<UnitType> {
        Measurement(value: lhs.value * rhs, unit: lhs.unit)
    }

    public static func * (lhs: Double, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        Measurement(value: lhs * rhs.value, unit: rhs.unit)
    }

    public static func / (lhs: Measurement<UnitType>, rhs: Double) -> Measurement<UnitType> {
        Measurement(value: lhs.value / rhs, unit: lhs.unit)
    }

    public static func / (lhs: Double, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        Measurement(value: lhs / rhs.value, unit: rhs.unit)
    }

    public static func += (lhs: inout Measurement<UnitType>, rhs: Measurement<UnitType>) { lhs = lhs + rhs }
    public static func -= (lhs: inout Measurement<UnitType>, rhs: Measurement<UnitType>) { lhs = lhs - rhs }
    public static func *= (lhs: inout Measurement<UnitType>, rhs: Double) { lhs.value *= rhs }
    public static func /= (lhs: inout Measurement<UnitType>, rhs: Double) { lhs.value /= rhs }
}

extension Measurement where UnitType: Dimension {
    /// The measurement in another unit of its dimension.
    public func converted(to otherUnit: UnitType) -> Measurement<UnitType> {
        if unit == otherUnit { return Measurement(value: value, unit: otherUnit) }
        let base = unit.converter.baseUnitValue(fromValue: value)
        return Measurement(value: otherUnit.converter.value(fromBaseUnitValue: base), unit: otherUnit)
    }

    public mutating func convert(to otherUnit: UnitType) {
        self = converted(to: otherUnit)
    }
}

extension Measurement: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSMeasurement

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSMeasurement {
        NSMeasurement(doubleValue: value, unit: unit)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSMeasurement, result: inout Measurement<UnitType>?) {
        result = Measurement(value: source.doubleValue, unit: source.unit as! UnitType)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSMeasurement, result: inout Measurement<UnitType>?) -> Bool {
        guard let unit = source.unit as? UnitType else { return false }
        result = Measurement(value: source.doubleValue, unit: unit)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSMeasurement?) -> Measurement<UnitType> {
        var result: Measurement<UnitType>?
        _forceBridgeFromObjectiveC(source!, result: &result)
        return result!
    }
}

extension MeasurementFormatter {
    /// A measurement as text.
    public func string<UnitType: Unit>(from measurement: Measurement<UnitType>) -> String {
        // The method Objective-C declares takes the measurement of any unit.
        let erased = Measurement<Unit>(value: measurement.value, unit: measurement.unit)
        return string(from: erased)
    }
}
