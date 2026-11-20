// Open-Meteo's forecast API (https://open-meteo.com/en/docs), answered as
// WeatherKit's types. It has no minute forecasts or alerts, and its day
// parts, twilight times and moon rise and set are worked out or left empty.

import CoreLocation
import Foundation

struct OpenMeteo: Sendable {
    var baseURL = URL(string: ProcessInfo.processInfo.environment["PERRY_WEATHERKIT_OPEN_METEO_URL"] ?? "https://api.open-meteo.com/v1/forecast")!

    var attribution: WeatherAttribution {
        WeatherAttribution(
            serviceName: "Open-Meteo.com",
            legalPageURL: URL(string: "https://open-meteo.com/en/license")!,
            squareMarkURL: URL(string: "https://open-meteo.com/images/logo.png")!,
            combinedMarkDarkURL: URL(string: "https://open-meteo.com/images/logo.png")!,
            combinedMarkLightURL: URL(string: "https://open-meteo.com/images/logo.png")!
        )
    }

    // MARK: Response

    private struct Response: Decodable {
        var utc_offset_seconds: Int
        var current: Current
        var hourly: Hourly
        var daily: Daily

        struct Current: Decodable {
            var time: Int
        }

        struct Hourly: Decodable {
            var time: [Int]
            var temperature_2m: [Double?]
            var apparent_temperature: [Double?]
            var relative_humidity_2m: [Double?]
            var dew_point_2m: [Double?]
            var precipitation_probability: [Double?]
            var precipitation: [Double?]
            var rain: [Double?]
            var snowfall: [Double?]
            var weather_code: [Int?]
            var pressure_msl: [Double?]
            var cloud_cover: [Double?]
            var cloud_cover_low: [Double?]
            var cloud_cover_mid: [Double?]
            var cloud_cover_high: [Double?]
            var visibility: [Double?]
            var wind_speed_10m: [Double?]
            var wind_direction_10m: [Double?]
            var wind_gusts_10m: [Double?]
            var uv_index: [Double?]
            var is_day: [Int?]
        }

        struct Daily: Decodable {
            var time: [Int]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
            var sunrise: [Int?]
            var sunset: [Int?]
            var uv_index_max: [Double?]
            var precipitation_sum: [Double?]
            var rain_sum: [Double?]
            var snowfall_sum: [Double?]
            var precipitation_probability_max: [Double?]
            var wind_speed_10m_max: [Double?]
            var wind_gusts_10m_max: [Double?]
            var wind_direction_10m_dominant: [Double?]
        }
    }

    // MARK: Request

    func weather(latitude: Double, longitude: Double) async throws -> Weather {
        let hourly = "temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation_probability,precipitation,rain,snowfall,"
            + "weather_code,pressure_msl,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,wind_speed_10m,"
            + "wind_direction_10m,wind_gusts_10m,uv_index,is_day"
        let daily = "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum,rain_sum,snowfall_sum,"
            + "precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant"
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "hourly", value: hourly),
            URLQueryItem(name: "daily", value: daily),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "forecast_days", value: "10"),
        ]
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: components.url!)
        } catch {
            throw WeatherError.unknown
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 { throw WeatherError.permissionDenied }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw WeatherError.unknown
        }
        return convert(decoded, latitude: latitude, longitude: longitude)
    }

    // MARK: Conversion

    private func convert(_ response: Response, latitude: Double, longitude: Double) -> Weather {
        let now = Date()
        let metadata = WeatherMetadata(date: now, expirationDate: now.addingTimeInterval(15 * 60), latitude: latitude, longitude: longitude)
        let h = response.hourly
        let hours: [HourWeather] = h.time.indices.map { i in
            hour(h, i)
        }
        let current = hours.last { $0.date <= now } ?? hours[0]
        let currentWeather = CurrentWeather(
            date: current.date, cloudCover: current.cloudCover, cloudCoverByAltitude: current.cloudCoverByAltitude,
            condition: current.condition, symbolName: current.symbolName, dewPoint: current.dewPoint, humidity: current.humidity,
            precipitationIntensity: Measurement(value: current.precipitationAmount.converted(to: .millimeters).value, unit: UnitSpeed.millimetersPerHour),
            pressure: current.pressure, pressureTrend: current.pressureTrend, isDaylight: current.isDaylight,
            temperature: current.temperature, apparentTemperature: current.apparentTemperature, uvIndex: current.uvIndex,
            visibility: current.visibility, wind: current.wind, metadata: metadata)
        let d = response.daily
        let offset = TimeInterval(response.utc_offset_seconds)
        let days: [DayWeather] = d.time.indices.map { i in
            let start = Date(timeIntervalSince1970: TimeInterval(d.time[i]) - offset)
            let end = start.addingTimeInterval(86_400)
            let ofDay = hours.filter { $0.date >= start && $0.date < end }
            return day(d, i, start: start, hours: ofDay, now: now)
        }
        return Weather(
            currentWeather: currentWeather, minuteForecast: nil,
            hourlyForecast: Forecast(forecast: hours.filter { $0.date >= now.addingTimeInterval(-3600) }, metadata: metadata),
            dailyForecast: Forecast(forecast: days, metadata: metadata), weatherAlerts: nil,
            availability: WeatherAvailability(minuteAvailability: .unsupported, alertAvailability: .unsupported))
    }

    private func value(_ array: [Double?], _ i: Int) -> Double { i < array.count ? (array[i] ?? 0) : 0 }

    private func hour(_ h: Response.Hourly, _ i: Int) -> HourWeather {
        let code = i < h.weather_code.count ? (h.weather_code[i] ?? 0) : 0
        let isDay = i < h.is_day.count ? (h.is_day[i] ?? 1) == 1 : true
        let condition = OpenMeteo.condition(code: code)
        let precipitationMM = value(h.precipitation, i)
        let snowCM = value(h.snowfall, i)
        let previous = i > 0 ? value(h.pressure_msl, i - 1) : value(h.pressure_msl, i)
        let pressure = value(h.pressure_msl, i)
        let uv = Int(value(h.uv_index, i).rounded())
        return HourWeather(
            date: Date(timeIntervalSince1970: TimeInterval(h.time[i])),
            cloudCover: value(h.cloud_cover, i) / 100,
            cloudCoverByAltitude: CloudCoverByAltitude(low: value(h.cloud_cover_low, i) / 100, medium: value(h.cloud_cover_mid, i) / 100,
                                                       high: value(h.cloud_cover_high, i) / 100),
            condition: condition, symbolName: OpenMeteo.symbol(condition, isDay: isDay),
            dewPoint: Measurement(value: value(h.dew_point_2m, i), unit: .celsius), humidity: value(h.relative_humidity_2m, i) / 100,
            isDaylight: isDay, precipitation: OpenMeteo.precipitation(code: code, amount: precipitationMM),
            precipitationChance: value(h.precipitation_probability, i) / 100,
            precipitationAmount: Measurement(value: value(h.rain, i), unit: .millimeters),
            snowfallAmount: Measurement(value: snowCM * 10, unit: .millimeters),
            pressure: Measurement(value: pressure, unit: .hectopascals),
            pressureTrend: pressure - previous > 0.5 ? .rising : pressure - previous < -0.5 ? .falling : .steady,
            temperature: Measurement(value: value(h.temperature_2m, i), unit: .celsius),
            apparentTemperature: Measurement(value: value(h.apparent_temperature, i), unit: .celsius),
            uvIndex: OpenMeteo.uvIndex(uv), visibility: Measurement(value: value(h.visibility, i), unit: .meters),
            wind: OpenMeteo.wind(speed: value(h.wind_speed_10m, i), direction: value(h.wind_direction_10m, i), gust: value(h.wind_gusts_10m, i)))
    }

    private func day(_ d: Response.Daily, _ i: Int, start: Date, hours: [HourWeather], now: Date) -> DayWeather {
        let code = d.weather_code[i] ?? 0
        let condition = OpenMeteo.condition(code: code)
        let high = hours.max { $0.temperature < $1.temperature }, low = hours.min { $0.temperature < $1.temperature }
        let humidities = hours.map(\.humidity), visibilities = hours.map { $0.visibility.value }
        let rain = Measurement(value: value(d.rain_sum, i), unit: UnitLength.millimeters)
        let snow = Measurement(value: value(d.snowfall_sum, i) * 10, unit: UnitLength.millimeters)
        let total = Measurement(value: value(d.precipitation_sum, i), unit: UnitLength.millimeters)
        let amounts = PrecipitationAmountByType(
            hail: Measurement(value: 0, unit: .millimeters), mixed: Measurement(value: 0, unit: .millimeters), rainfall: rain,
            sleet: Measurement(value: 0, unit: .millimeters), precipitation: total, snowfallAmount: SnowfallAmount(amount: snow, snowfallAmount: snow))
        let sunrise = d.sunrise[i].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sunset = d.sunset[i].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let noon = sunrise.flatMap { rise in sunset.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 + rise.timeIntervalSince1970) / 2) } }
        let wind = OpenMeteo.wind(speed: value(d.wind_speed_10m_max, i), direction: value(d.wind_direction_10m_dominant, i),
                                  gust: value(d.wind_gusts_10m_max, i))
        let highT = Measurement(value: value(d.temperature_2m_max, i), unit: UnitTemperature.celsius)
        let lowT = Measurement(value: value(d.temperature_2m_min, i), unit: UnitTemperature.celsius)
        let cover = hours.isEmpty ? 0 : hours.map(\.cloudCover).reduce(0, +) / Double(hours.count)
        let chance = value(d.precipitation_probability_max, i) / 100
        func part(_ part: [HourWeather]) -> DayPartForecast {
            DayPartForecast(
                cloudCover: part.isEmpty ? cover : part.map(\.cloudCover).reduce(0, +) / Double(part.count),
                cloudCoverByAltitude: CloudCoverByAltitude(low: 0, medium: 0, high: 0), condition: condition,
                highTemperature: part.map(\.temperature).max() ?? highT, lowTemperature: part.map(\.temperature).min() ?? lowT,
                precipitation: OpenMeteo.precipitation(code: code, amount: value(d.precipitation_sum, i)), precipitationAmountByType: amounts,
                precipitationChance: part.map(\.precipitationChance).max() ?? chance, maximumHumidity: part.map(\.humidity).max() ?? 0,
                minimumHumidity: part.map(\.humidity).min() ?? 0, maximumVisibility: part.map(\.visibility).max() ?? Measurement(value: 0, unit: .meters),
                minimumVisibility: part.map(\.visibility).min() ?? Measurement(value: 0, unit: .meters), wind: wind,
                highWindSpeed: wind.gust ?? wind.speed)
        }
        let calendarHours = hours.map { ($0, Int(($0.date.timeIntervalSince(start) / 3600).rounded(.down))) }
        let daytime = calendarHours.filter { 6..<18 ~= $0.1 }.map(\.0)
        let overnight = calendarHours.filter { $0.1 >= 18 || $0.1 < 6 }.map(\.0)
        let rest = calendarHours.filter { $0.0.date >= now }.map(\.0)
        return DayWeather(
            date: start, condition: condition, symbolName: OpenMeteo.symbol(condition, isDay: true), highTemperature: highT,
            highTemperatureTime: high?.date, lowTemperature: lowT, lowTemperatureTime: low?.date, maximumHumidity: humidities.max() ?? 0,
            minimumHumidity: humidities.min() ?? 0, precipitation: OpenMeteo.precipitation(code: code, amount: value(d.precipitation_sum, i)),
            precipitationChance: chance, rainfallAmount: rain, snowfallAmount: snow, precipitationAmountByType: amounts,
            sun: SunEvents(sunrise: sunrise, solarNoon: noon, sunset: sunset),
            moon: MoonEvents(phase: OpenMeteo.moonPhase(on: start), moonrise: nil, moonset: nil),
            uvIndex: OpenMeteo.uvIndex(Int(value(d.uv_index_max, i).rounded())), maximumVisibility: visibilities.max() ?? 0,
            minimumVisibility: visibilities.min() ?? 0, wind: wind, highWindSpeed: wind.gust,
            daytimeForecast: part(daytime), overnightForecast: part(overnight), restOfDayForecast: rest.isEmpty ? nil : part(rest))
    }

    // MARK: Codes

    /// A WMO weather code, as a condition.
    static func condition(code: Int) -> WeatherCondition {
        switch code {
        case 0: .clear
        case 1: .mostlyClear
        case 2: .partlyCloudy
        case 3: .cloudy
        case 45, 48: .foggy
        case 51, 53, 55: .drizzle
        case 56, 57: .freezingDrizzle
        case 61, 63: .rain
        case 65: .heavyRain
        case 66, 67: .freezingRain
        case 71, 77: .flurries
        case 73: .snow
        case 75: .heavySnow
        case 80: .sunShowers
        case 81: .rain
        case 82: .heavyRain
        case 85: .sunFlurries
        case 86: .heavySnow
        case 95: .thunderstorms
        case 96, 99: .strongStorms
        default: .clear
        }
    }

    static func precipitation(code: Int, amount: Double) -> Precipitation {
        switch code {
        case 51...57, 61...65, 80...82, 95: amount > 0 ? .rain : .none
        case 66, 67: .sleet
        case 71...77, 85, 86: .snow
        case 96, 99: .hail
        default: amount > 0 ? .rain : .none
        }
    }

    static func symbol(_ condition: WeatherCondition, isDay: Bool) -> String {
        switch condition {
        case .clear: isDay ? "sun.max" : "moon.stars"
        case .mostlyClear, .partlyCloudy: isDay ? "cloud.sun" : "cloud.moon"
        case .cloudy, .mostlyCloudy: "cloud"
        case .foggy, .haze, .smoky, .blowingDust: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .rain, .sunShowers: isDay ? "cloud.sun.rain" : "cloud.moon.rain"
        case .heavyRain: "cloud.heavyrain"
        case .freezingDrizzle, .freezingRain, .sleet, .wintryMix: "cloud.sleet"
        case .flurries, .sunFlurries, .snow, .blowingSnow, .blizzard, .heavySnow: "cloud.snow"
        case .hail: "cloud.hail"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .tropicalStorm: "cloud.bolt.rain"
        case .hurricane: "hurricane"
        case .windy, .breezy: "wind"
        case .frigid: "thermometer.snowflake"
        case .hot: "thermometer.sun"
        }
    }

    static func uvIndex(_ value: Int) -> UVIndex {
        let category = UVIndex.ExposureCategory.allCases.first { $0.rangeValue.contains(value) } ?? .low
        return UVIndex(value: value, category: category)
    }

    static func wind(speed: Double, direction: Double, gust: Double) -> Wind {
        let sector = Int(((direction.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return Wind(compassDirection: Wind.CompassDirection.allCases[sector], direction: Measurement(value: direction, unit: .degrees),
                    speed: Measurement(value: speed, unit: .metersPerSecond), gust: Measurement(value: gust, unit: .metersPerSecond))
    }

    /// The moon's phase from the mean synodic month.
    static func moonPhase(on date: Date) -> MoonPhase {
        let days = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_550.1
        let fraction = (days / 29.530588853).truncatingRemainder(dividingBy: 1)
        let position = fraction < 0 ? fraction + 1 : fraction
        let index = Int((position * 8).rounded()) % 8
        return MoonPhase.allCases[index]
    }
}

extension UnitSpeed {
    /// Rain's intensity, as WeatherKit gives it.
    static let millimetersPerHour = UnitSpeed(symbol: "mm/hr", converter: UnitConverterLinear(coefficient: 1 / 3_600_000))
}
