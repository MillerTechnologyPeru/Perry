// WeatherKit's weather data: the values a forecast is made of. The
// declarations follow the iOS SDK's WeatherKit interface (frozen enums and
// their cases) so apps built against Apple's bind to them by the same
// symbols; the layouts of the others are this framework's, which the
// interface leaves to it.

public import CoreLocation
public import Foundation

// MARK: - Conditions

public enum WeatherCondition: String, CaseIterable, CustomStringConvertible, Hashable, Codable, Sendable {
    case blizzard, blowingDust, blowingSnow, breezy, clear, cloudy, drizzle, flurries, foggy, freezingDrizzle
    case freezingRain, frigid, hail, haze, heavyRain, heavySnow, hot, hurricane, isolatedThunderstorms
    case mostlyClear, mostlyCloudy, partlyCloudy, rain, scatteredThunderstorms, sleet, smoky, snow, strongStorms
    case sunFlurries, sunShowers, thunderstorms, tropicalStorm, windy, wintryMix

    public var description: String {
        switch self {
        case .blizzard: "Blizzard"
        case .blowingDust: "Blowing Dust"
        case .blowingSnow: "Blowing Snow"
        case .breezy: "Breezy"
        case .clear: "Clear"
        case .cloudy: "Cloudy"
        case .drizzle: "Drizzle"
        case .flurries: "Flurries"
        case .foggy: "Foggy"
        case .freezingDrizzle: "Freezing Drizzle"
        case .freezingRain: "Freezing Rain"
        case .frigid: "Frigid"
        case .hail: "Hail"
        case .haze: "Haze"
        case .heavyRain: "Heavy Rain"
        case .heavySnow: "Heavy Snow"
        case .hot: "Hot"
        case .hurricane: "Hurricane"
        case .isolatedThunderstorms: "Isolated Thunderstorms"
        case .mostlyClear: "Mostly Clear"
        case .mostlyCloudy: "Mostly Cloudy"
        case .partlyCloudy: "Partly Cloudy"
        case .rain: "Rain"
        case .scatteredThunderstorms: "Scattered Thunderstorms"
        case .sleet: "Sleet"
        case .smoky: "Smoky"
        case .snow: "Snow"
        case .strongStorms: "Strong Storms"
        case .sunFlurries: "Sun Flurries"
        case .sunShowers: "Sun Showers"
        case .thunderstorms: "Thunderstorms"
        case .tropicalStorm: "Tropical Storm"
        case .windy: "Windy"
        case .wintryMix: "Wintry Mix"
        }
    }

    public var accessibilityDescription: String { description }
}

public enum Precipitation: String, CaseIterable, CustomStringConvertible, Hashable, Codable, Sendable {
    case none, hail, mixed, rain, sleet, snow

    public var description: String {
        switch self {
        case .none: "None"
        case .hail: "Hail"
        case .mixed: "Mixed"
        case .rain: "Rain"
        case .sleet: "Sleet"
        case .snow: "Snow"
        }
    }

    public var accessibilityDescription: String { description }
}

public enum PressureTrend: String, CaseIterable, CustomStringConvertible, Hashable, Codable, Sendable {
    case rising, falling, steady

    public var description: String {
        switch self {
        case .rising: "Rising"
        case .falling: "Falling"
        case .steady: "Steady"
        }
    }

    public var accessibilityDescription: String { description }
}

public enum WeatherSeverity: String, CaseIterable, CustomStringConvertible, Hashable, Codable, Sendable {
    case minor, moderate, severe, extreme, unknown

    public var description: String {
        switch self {
        case .minor: "Minor"
        case .moderate: "Moderate"
        case .severe: "Severe"
        case .extreme: "Extreme"
        case .unknown: "Unknown"
        }
    }

    public var accessibilityDescription: String { description }
}

@frozen public enum MoonPhase: String, CustomStringConvertible, CaseIterable, Codable, Sendable {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent

    public var description: String {
        switch self {
        case .new: "New"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .full: "Full"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
        }
    }

    public var accessibilityDescription: String { description }

    public var symbolName: String {
        switch self {
        case .new: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .full: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }
}

// MARK: - Values

public struct Wind: Codable, Equatable, Sendable {
    public var compassDirection: Wind.CompassDirection
    public var direction: Measurement<UnitAngle>
    public var speed: Measurement<UnitSpeed>
    public var gust: Measurement<UnitSpeed>?

    @frozen public enum CompassDirection: String, Codable, CaseIterable, CustomStringConvertible, Sendable {
        case north, northNortheast, northeast, eastNortheast, east, eastSoutheast, southeast, southSoutheast
        case south, southSouthwest, southwest, westSouthwest, west, westNorthwest, northwest, northNorthwest

        public var abbreviation: String {
            switch self {
            case .north: "N"
            case .northNortheast: "NNE"
            case .northeast: "NE"
            case .eastNortheast: "ENE"
            case .east: "E"
            case .eastSoutheast: "ESE"
            case .southeast: "SE"
            case .southSoutheast: "SSE"
            case .south: "S"
            case .southSouthwest: "SSW"
            case .southwest: "SW"
            case .westSouthwest: "WSW"
            case .west: "W"
            case .westNorthwest: "WNW"
            case .northwest: "NW"
            case .northNorthwest: "NNW"
            }
        }

        public var description: String {
            switch self {
            case .north: "North"
            case .northNortheast: "North-Northeast"
            case .northeast: "Northeast"
            case .eastNortheast: "East-Northeast"
            case .east: "East"
            case .eastSoutheast: "East-Southeast"
            case .southeast: "Southeast"
            case .southSoutheast: "South-Southeast"
            case .south: "South"
            case .southSouthwest: "South-Southwest"
            case .southwest: "Southwest"
            case .westSouthwest: "West-Southwest"
            case .west: "West"
            case .westNorthwest: "West-Northwest"
            case .northwest: "Northwest"
            case .northNorthwest: "North-Northwest"
            }
        }

        public var accessibilityDescription: String { description }
    }
}

public struct UVIndex: Codable, Equatable, Sendable {
    public var value: Int
    public var category: UVIndex.ExposureCategory

    @frozen public enum ExposureCategory: String, Codable, Comparable, CustomStringConvertible, CaseIterable, Sendable {
        case low, moderate, high, veryHigh, extreme

        public var rangeValue: ClosedRange<Int> {
            switch self {
            case .low: 0...2
            case .moderate: 3...5
            case .high: 6...7
            case .veryHigh: 8...10
            case .extreme: 11...Int.max
            }
        }

        public var description: String {
            switch self {
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            case .veryHigh: "Very High"
            case .extreme: "Extreme"
            }
        }

        public var accessibilityDescription: String { description }

        public static func < (lhs: ExposureCategory, rhs: ExposureCategory) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }
}

public struct CloudCoverByAltitude: Codable, Equatable, Sendable {
    public var low: Double
    public var medium: Double
    public var high: Double
}

public struct SunEvents: Codable, Equatable, Sendable {
    public var astronomicalDawn: Date?
    public var nauticalDawn: Date?
    public var civilDawn: Date?
    public var sunrise: Date?
    public var solarNoon: Date?
    public var sunset: Date?
    public var civilDusk: Date?
    public var nauticalDusk: Date?
    public var astronomicalDusk: Date?
    public var solarMidnight: Date?
}

public struct MoonEvents: Codable, Equatable, Sendable {
    public var phase: MoonPhase
    public var moonrise: Date?
    public var moonset: Date?
}

public struct SnowfallAmount: Codable, Equatable, Sendable {
    public var amount: Measurement<UnitLength>
    public var snowfallAmount: Measurement<UnitLength>
}

public struct PrecipitationAmountByType: Codable, Equatable, Sendable {
    public var hail: Measurement<UnitLength>
    public var mixed: Measurement<UnitLength>
    public var rainfall: Measurement<UnitLength>
    public var sleet: Measurement<UnitLength>
    public var precipitation: Measurement<UnitLength>
    public var snowfallAmount: SnowfallAmount
}

// MARK: - Metadata and attribution

public struct WeatherMetadata: Codable, Equatable, Sendable {
    public var date: Date
    public var expirationDate: Date
    var latitude: Double
    var longitude: Double

    public var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

public struct WeatherAttribution: Codable, Equatable, Sendable {
    public var serviceName: String
    public var legalPageURL: URL
    public var squareMarkURL: URL
    public var combinedMarkDarkURL: URL
    public var combinedMarkLightURL: URL

    public var legalAttributionText: String { "Weather data by \(serviceName)" }
}

public enum WeatherError: LocalizedError, Hashable, Sendable {
    case permissionDenied
    case unknown

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Weather data isn't available to this app."
        case .unknown: "The weather couldn't be loaded."
        }
    }

    public var failureReason: String? {
        switch self {
        case .permissionDenied: "The app isn't allowed to use the weather service."
        case .unknown: "The weather service didn't answer."
        }
    }

    public var helpAnchor: String? { nil }

    public var recoverySuggestion: String? {
        switch self {
        case .permissionDenied: "Check the app's WeatherKit access."
        case .unknown: "Try again later."
        }
    }
}

// MARK: - Weather by the minute, hour and day

public struct MinuteWeather: Codable, Equatable, Sendable {
    public var date: Date
    public var precipitation: Precipitation
    public var precipitationChance: Double
    public var precipitationIntensity: Measurement<UnitSpeed>
}

public struct HourWeather: Codable, Equatable, Sendable {
    public var date: Date
    public var cloudCover: Double
    public var cloudCoverByAltitude: CloudCoverByAltitude
    public var condition: WeatherCondition
    public var symbolName: String
    public var dewPoint: Measurement<UnitTemperature>
    public var humidity: Double
    public var isDaylight: Bool
    public var precipitation: Precipitation
    public var precipitationChance: Double
    public var precipitationAmount: Measurement<UnitLength>
    public var snowfallAmount: Measurement<UnitLength>
    public var pressure: Measurement<UnitPressure>
    public var pressureTrend: PressureTrend
    public var temperature: Measurement<UnitTemperature>
    public var apparentTemperature: Measurement<UnitTemperature>
    public var uvIndex: UVIndex
    public var visibility: Measurement<UnitLength>
    public var wind: Wind
}

public struct DayPartForecast: Codable, Equatable, Sendable {
    public var cloudCover: Double
    public var cloudCoverByAltitude: CloudCoverByAltitude
    public var condition: WeatherCondition
    public var highTemperature: Measurement<UnitTemperature>
    public var lowTemperature: Measurement<UnitTemperature>
    public var precipitation: Precipitation
    public var precipitationAmountByType: PrecipitationAmountByType
    public var precipitationChance: Double
    public var maximumHumidity: Double
    public var minimumHumidity: Double
    public var maximumVisibility: Measurement<UnitLength>
    public var minimumVisibility: Measurement<UnitLength>
    public var wind: Wind
    public var highWindSpeed: Measurement<UnitSpeed>
}

public struct DayWeather: Codable, Equatable, Sendable {
    public var date: Date
    public var condition: WeatherCondition
    public var symbolName: String
    public var highTemperature: Measurement<UnitTemperature>
    public var highTemperatureTime: Date?
    public var lowTemperature: Measurement<UnitTemperature>
    public var lowTemperatureTime: Date?
    public var maximumHumidity: Double
    public var minimumHumidity: Double
    public var precipitation: Precipitation
    public var precipitationChance: Double
    public var precipitationAmount: Measurement<UnitLength> { rainfallAmount }
    public var rainfallAmount: Measurement<UnitLength>
    public var snowfallAmount: Measurement<UnitLength>
    public var precipitationAmountByType: PrecipitationAmountByType
    public var sun: SunEvents
    public var moon: MoonEvents
    public var uvIndex: UVIndex
    public var maximumVisibility: Double
    public var minimumVisibility: Double
    public var wind: Wind
    public var highWindSpeed: Measurement<UnitSpeed>?
    public var daytimeForecast: DayPartForecast
    public var overnightForecast: DayPartForecast
    public var restOfDayForecast: DayPartForecast?

    private enum CodingKeys: String, CodingKey {
        case date, condition, symbolName, highTemperature, highTemperatureTime, lowTemperature, lowTemperatureTime
        case maximumHumidity, minimumHumidity, precipitation, precipitationChance, rainfallAmount, snowfallAmount
        case precipitationAmountByType, sun, moon, uvIndex, maximumVisibility, minimumVisibility, wind, highWindSpeed
        case daytimeForecast, overnightForecast, restOfDayForecast
    }
}

public struct CurrentWeather: Codable, Equatable, Sendable {
    public var date: Date
    public var cloudCover: Double
    public var cloudCoverByAltitude: CloudCoverByAltitude
    public var condition: WeatherCondition
    public var symbolName: String
    public var dewPoint: Measurement<UnitTemperature>
    public var humidity: Double
    public var precipitationIntensity: Measurement<UnitSpeed>
    public var pressure: Measurement<UnitPressure>
    public var pressureTrend: PressureTrend
    public var isDaylight: Bool
    public var temperature: Measurement<UnitTemperature>
    public var apparentTemperature: Measurement<UnitTemperature>
    public var uvIndex: UVIndex
    public var visibility: Measurement<UnitLength>
    public var wind: Wind
    public var metadata: WeatherMetadata
}

public struct WeatherAlert: Codable, Equatable, Sendable {
    public var detailsURL: URL
    public var source: String
    public var summary: String
    public var region: String?
    public var severity: WeatherSeverity
    public var metadata: WeatherMetadata
}

public struct WeatherAvailability: Codable, Equatable, Sendable {
    public var minuteAvailability: WeatherAvailability.AvailabilityKind
    public var alertAvailability: WeatherAvailability.AvailabilityKind

    public enum AvailabilityKind: String, Codable, Hashable, Equatable, Sendable {
        case available, temporarilyUnavailable, unsupported, unknown
    }
}
