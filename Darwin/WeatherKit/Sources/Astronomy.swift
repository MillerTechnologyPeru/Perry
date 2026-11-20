// The sun's and moon's events for a day, worked out from where and when:
// Open-Meteo gives sunrise and sunset, and WeatherKit's apps expect the
// twilights, solar noon and midnight, and the moon's rise and set too.
// The sun is NOAA's solar calculator; the moon is the low-precision
// position of SunCalc, found crossing the horizon hour by hour.

import Foundation

enum Astronomy {
    private static let radians = Double.pi / 180
    private static let julianEpoch = 2_440_587.5

    // MARK: Sun

    struct SunTimes {
        var solarNoon: Date
        var solarMidnight: Date
        var civilDawn, civilDusk, nauticalDawn, nauticalDusk, astronomicalDawn, astronomicalDusk, sunrise, sunset: Date?
    }

    /// The sun's events for the day that starts at `start` (and lasts 24 hours).
    static func sun(dayStarting start: Date, latitude: Double, longitude: Double) -> SunTimes {
        let guess = start.addingTimeInterval(12 * 3600)
        let julian = guess.timeIntervalSince1970 / 86_400 + julianEpoch
        let t = (julian - 2_451_545) / 36_525
        let l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * radians) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m * radians) * (0.019993 - 0.000101 * t)
            + sin(3 * m * radians) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(omega * radians)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(omega * radians)
        let declination = asin(sin(eps * radians) * sin(lambda * radians))
        let y = pow(tan(eps * radians / 2), 2)
        let equationOfTime = 4 / radians * (y * sin(2 * l0 * radians) - 2 * e * sin(m * radians)
            + 4 * e * y * sin(m * radians) * cos(2 * l0 * radians) - 0.5 * y * y * sin(4 * l0 * radians) - 1.25 * e * e * sin(2 * m * radians))
        // Minutes after midnight UTC, on the UTC day that puts it nearest the guess.
        let minutes = 720 - 4 * longitude - equationOfTime
        let day = ((guess.timeIntervalSince1970 / 60 - minutes) / 1440).rounded()
        let noon = Date(timeIntervalSince1970: (day * 1440 + minutes) * 60)

        func event(altitude: Double, rising: Bool) -> Date? {
            let phi = latitude * radians
            let cosH = (sin(altitude * radians) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
            guard abs(cosH) <= 1 else { return nil }
            let h = acos(cosH) / radians
            return noon.addingTimeInterval((rising ? -4 : 4) * h * 60)
        }
        let before = noon.addingTimeInterval(-12 * 3600), after = noon.addingTimeInterval(12 * 3600)
        let midnight = before >= start ? before : after
        return SunTimes(
            solarNoon: noon, solarMidnight: midnight,
            civilDawn: event(altitude: -6, rising: true), civilDusk: event(altitude: -6, rising: false),
            nauticalDawn: event(altitude: -12, rising: true), nauticalDusk: event(altitude: -12, rising: false),
            astronomicalDawn: event(altitude: -18, rising: true), astronomicalDusk: event(altitude: -18, rising: false),
            sunrise: event(altitude: -0.833, rising: true), sunset: event(altitude: -0.833, rising: false))
    }

    // MARK: Moon

    private static func moonAltitude(_ date: Date, latitude: Double, longitude: Double) -> Double {
        let d = date.timeIntervalSince1970 / 86_400 + julianEpoch - 2_451_545
        let l = radians * (218.316 + 13.176396 * d), m = radians * (134.963 + 13.064993 * d), f = radians * (93.272 + 13.229350 * d)
        let lon = l + radians * 6.289 * sin(m), lat = radians * 5.128 * sin(f)
        let e = radians * 23.4397
        let ra = atan2(sin(lon) * cos(e) - tan(lat) * sin(e), cos(lon))
        let dec = asin(sin(lat) * cos(e) + cos(lat) * sin(e) * sin(lon))
        let lw = radians * -longitude, phi = radians * latitude
        let h = radians * (280.16 + 360.9856235 * d) - lw - ra
        var altitude = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
        altitude += radians * 0.017 / tan(altitude + radians * 10.26 / (altitude + radians * 5.10))
        return altitude
    }

    /// The moon's rise and set within the 24 hours from `start`.
    static func moon(dayStarting start: Date, latitude: Double, longitude: Double) -> (rise: Date?, set: Date?) {
        let horizon = radians * 0.133
        func altitude(_ hour: Double) -> Double {
            moonAltitude(start.addingTimeInterval(hour * 3600), latitude: latitude, longitude: longitude) - horizon
        }
        var rise: Double?, set: Double?
        var h0 = altitude(0)
        var i = 1.0
        while i <= 24 {
            let h1 = altitude(i), h2 = altitude(i + 1)
            let a = (h0 + h2) / 2 - h1, b = (h2 - h0) / 2
            let xe = -b / (2 * a), ye = (a * xe + b) * xe + h1
            let discriminant = b * b - 4 * a * h1
            var roots = 0
            var x1 = 0.0, x2 = 0.0
            if discriminant >= 0 {
                let dx = discriminant.squareRoot() / (abs(a) * 2)
                x1 = xe - dx
                x2 = xe + dx
                if abs(x1) <= 1 { roots += 1 }
                if abs(x2) <= 1 { roots += 1 }
                if x1 < -1 { x1 = x2 }
            }
            if roots == 1 {
                if h0 < 0 { rise = i + x1 } else { set = i + x1 }
            } else if roots == 2 {
                rise = i + (ye < 0 ? x2 : x1)
                set = i + (ye < 0 ? x1 : x2)
            }
            if rise != nil, set != nil { break }
            h0 = h2
            i += 2
        }
        return (rise.map { start.addingTimeInterval($0 * 3600) }, set.map { start.addingTimeInterval($0 * 3600) })
    }
}
