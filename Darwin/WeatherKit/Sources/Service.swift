// WeatherService, the queries it answers and the forecasts it returns. The
// data comes from Open-Meteo, which needs no account or key (its terms ask
// for attribution, which `WeatherService.attribution` carries).

public import CoreLocation
public import Foundation

// MARK: - Forecasts

public struct Forecast<Element>: RandomAccessCollection, Codable, Equatable, Sendable
    where Element: Decodable, Element: Encodable, Element: Equatable, Element: Sendable {
    public typealias Index = Int
    public var forecast: [Element]
    public var metadata: WeatherMetadata
    public var startIndex: Int { forecast.startIndex }
    public var endIndex: Int { forecast.endIndex }
    public subscript(position: Int) -> Element { forecast[position] }
}

extension Forecast where Element == MinuteWeather {
    public var summary: String { "" }
}

public struct Weather: Codable, Equatable, Sendable {
    public var currentWeather: CurrentWeather
    public var minuteForecast: Forecast<MinuteWeather>?
    public var hourlyForecast: Forecast<HourWeather>
    public var dailyForecast: Forecast<DayWeather>
    public var weatherAlerts: [WeatherAlert]?
    public var availability: WeatherAvailability
}

// MARK: - Queries

public struct WeatherQuery<T> {
    let extract: @Sendable (Weather) -> T

    public static var current: WeatherQuery<CurrentWeather> { WeatherQuery<CurrentWeather> { $0.currentWeather } }
    public static var minute: WeatherQuery<Forecast<MinuteWeather>?> { WeatherQuery<Forecast<MinuteWeather>?> { $0.minuteForecast } }
    public static var hourly: WeatherQuery<Forecast<HourWeather>> { WeatherQuery<Forecast<HourWeather>> { $0.hourlyForecast } }
    public static var daily: WeatherQuery<Forecast<DayWeather>> { WeatherQuery<Forecast<DayWeather>> { $0.dailyForecast } }
    public static var alerts: WeatherQuery<[WeatherAlert]?> { WeatherQuery<[WeatherAlert]?> { $0.weatherAlerts } }
    public static var availability: WeatherQuery<WeatherAvailability> { WeatherQuery<WeatherAvailability> { $0.availability } }
}

extension WeatherQuery: Sendable {}

extension WeatherQuery where T == Forecast<DayWeather> {
    public static func daily(startDate: Date, endDate: Date) -> WeatherQuery<T> {
        WeatherQuery<T> { weather in
            var days = weather.dailyForecast
            days.forecast = days.forecast.filter { $0.date >= startDate && $0.date <= endDate }
            return days
        }
    }
}

extension WeatherQuery where T == Forecast<HourWeather> {
    public static func hourly(startDate: Date, endDate: Date) -> WeatherQuery<T> {
        WeatherQuery<T> { weather in
            var hours = weather.hourlyForecast
            hours.forecast = hours.forecast.filter { $0.date >= startDate && $0.date <= endDate }
            return hours
        }
    }
}

// MARK: - The service

final public class WeatherService: @unchecked Sendable {
    public static let shared = WeatherService()

    public convenience init() { self.init(backend: OpenMeteo()) }

    private let backend: OpenMeteo

    private init(backend: OpenMeteo) { self.backend = backend }

    final public var attribution: WeatherAttribution {
        get async throws { backend.attribution }
    }

    final public func weather(for location: CLLocation) async throws -> Weather {
        try await backend.weather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    @preconcurrency
    final public func weather<T>(for location: CLLocation, including dataSet: WeatherQuery<T>) async throws -> T where T: Sendable {
        dataSet.extract(try await weather(for: location))
    }

    @preconcurrency
    final public func weather<T1, T2>(for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>) async throws
        -> (T1, T2) where T1: Sendable, T2: Sendable {
        let weather = try await weather(for: location)
        return (dataSet1.extract(weather), dataSet2.extract(weather))
    }

    @preconcurrency
    final public func weather<T1, T2, T3>(for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
                                          _ dataSet3: WeatherQuery<T3>) async throws -> (T1, T2, T3)
        where T1: Sendable, T2: Sendable, T3: Sendable {
        let weather = try await weather(for: location)
        return (dataSet1.extract(weather), dataSet2.extract(weather), dataSet3.extract(weather))
    }

    @preconcurrency
    final public func weather<T1, T2, T3, T4>(for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
                                              _ dataSet3: WeatherQuery<T3>, _ dataSet4: WeatherQuery<T4>) async throws -> (T1, T2, T3, T4)
        where T1: Sendable, T2: Sendable, T3: Sendable, T4: Sendable {
        let weather = try await weather(for: location)
        return (dataSet1.extract(weather), dataSet2.extract(weather), dataSet3.extract(weather), dataSet4.extract(weather))
    }

    @preconcurrency
    final public func weather<T1, T2, T3, T4, T5>(for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
                                                  _ dataSet3: WeatherQuery<T3>, _ dataSet4: WeatherQuery<T4>,
                                                  _ dataSet5: WeatherQuery<T5>) async throws -> (T1, T2, T3, T4, T5)
        where T1: Sendable, T2: Sendable, T3: Sendable, T4: Sendable, T5: Sendable {
        let weather = try await weather(for: location)
        return (dataSet1.extract(weather), dataSet2.extract(weather), dataSet3.extract(weather), dataSet4.extract(weather),
                dataSet5.extract(weather))
    }

    @preconcurrency
    final public func weather<T1, T2, T3, T4, T5, T6>(for location: CLLocation, including dataSet1: WeatherQuery<T1>,
                                                      _ dataSet2: WeatherQuery<T2>, _ dataSet3: WeatherQuery<T3>,
                                                      _ dataSet4: WeatherQuery<T4>, _ dataSet5: WeatherQuery<T5>,
                                                      _ dataSet6: WeatherQuery<T6>) async throws -> (T1, T2, T3, T4, T5, T6)
        where T1: Sendable, T2: Sendable, T3: Sendable, T4: Sendable, T5: Sendable, T6: Sendable {
        let weather = try await weather(for: location)
        return (dataSet1.extract(weather), dataSet2.extract(weather), dataSet3.extract(weather), dataSet4.extract(weather),
                dataSet5.extract(weather), dataSet6.extract(weather))
    }

    @preconcurrency
    final public func weather<each T>(for location: CLLocation, including dataSet: repeat WeatherQuery<each T>) async throws
        -> (repeat each T) where repeat each T: Sendable {
        let weather = try await weather(for: location)
        return (repeat (each dataSet).extract(weather))
    }
}
