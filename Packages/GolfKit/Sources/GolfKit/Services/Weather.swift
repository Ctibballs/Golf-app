import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// WMO weather interpretation codes as used by Open-Meteo.
public struct WeatherCondition: Hashable, Sendable {
    public var code: Int

    public init(code: Int) { self.code = code }

    public var description: String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81: return "Showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }

    public func symbolName(isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    public var isWet: Bool { (51...99).contains(code) }
    public var isStormy: Bool { code >= 95 }
}

public struct CurrentWeather: Codable, Hashable, Sendable {
    public var time: Date
    public var temperature: Double
    public var apparentTemperature: Double?
    public var humidity: Double?
    public var precipitation: Double
    public var weatherCode: Int
    public var windSpeed: Double
    public var windGusts: Double?
    /// Direction the wind blows FROM, degrees clockwise from north.
    public var windDirection: Double
    public var isDay: Bool

    public var condition: WeatherCondition { WeatherCondition(code: weatherCode) }
}

public struct HourlyWeather: Codable, Hashable, Identifiable, Sendable {
    public var time: Date
    public var temperature: Double
    public var precipitationProbability: Double?
    public var weatherCode: Int
    public var windSpeed: Double
    public var windDirection: Double

    public var id: Date { time }
    public var condition: WeatherCondition { WeatherCondition(code: weatherCode) }
}

public struct DailyWeather: Codable, Hashable, Identifiable, Sendable {
    public var date: Date
    public var high: Double
    public var low: Double
    public var precipitationProbability: Double?
    public var weatherCode: Int
    public var maxWind: Double?
    public var sunrise: Date?
    public var sunset: Date?

    public var id: Date { date }
    public var condition: WeatherCondition { WeatherCondition(code: weatherCode) }
}

/// Weather for a course. All values SI: °C, km/h, mm.
public struct WeatherReport: Codable, Hashable, Sendable {
    public var location: GeoPoint
    public var timezone: String?
    public var current: CurrentWeather
    public var hourly: [HourlyWeather]
    public var daily: [DailyWeather]
    public var fetchedAt: Date

    /// Hours from now (inclusive of the current hour), for an at-a-glance strip.
    public func upcomingHours(from now: Date = Date(), count: Int = 6) -> [HourlyWeather] {
        let start = now.addingTimeInterval(-3600)
        return Array(hourly.filter { $0.time > start }.prefix(count))
    }

    /// One-line summary saved with rounds: "Partly cloudy, 18°C, wind 12 km/h".
    public func summary(units: UnitFormatter) -> String {
        "\(current.condition.description), \(units.temperature(current.temperature, includeUnit: true)), wind \(units.windSpeed(current.windSpeed))"
    }

    public var playability: Playability { Playability(current: current, nextHours: upcomingHours(from: current.time, count: 4)) }
}

/// A quick verdict on whether it's a good time to play.
public struct Playability: Hashable, Sendable {
    public var score: Int
    public var headline: String

    public init(current: CurrentWeather, nextHours: [HourlyWeather]) {
        var score = 100.0
        let wind = max(current.windSpeed, (current.windGusts ?? 0) * 0.7)
        score -= max(0, wind - 12) * 1.4
        let rainChance = nextHours.compactMap(\.precipitationProbability).max() ?? (current.condition.isWet ? 80 : 0)
        score -= rainChance * 0.35
        if current.precipitation > 0 { score -= 15 }
        let feels = current.apparentTemperature ?? current.temperature
        if feels < 8 { score -= (8 - feels) * 3 }
        if feels > 30 { score -= (feels - 30) * 3 }
        if current.condition.isStormy || nextHours.contains(where: { $0.condition.isStormy }) { score = min(score, 10) }
        let clamped = Int(max(0, min(100, score)).rounded())
        self.score = clamped

        switch clamped {
        case 85...: headline = "Perfect golf weather"
        case 70..<85: headline = "Good conditions"
        case 50..<70: headline = wind > 25 ? "Breezy — club up" : "Playable, pack a layer"
        case 25..<50: headline = rainChance > 50 ? "Showers likely" : "Tough conditions"
        default: headline = current.condition.isStormy ? "Lightning risk — stay off the course" : "Better stay in the clubhouse"
        }
    }
}

/// How the wind affects a shot along a given bearing.
public struct WindEffect: Hashable, Sendable {
    /// Positive = helping (tailwind), negative = hurting (headwind), km/h.
    public var along: Double
    /// Positive = blowing left-to-right, km/h.
    public var across: Double

    public init(windSpeed: Double, windFromDirection: Double, shotBearing: Double) {
        // Wind blows TOWARDS the opposite of where it comes from.
        let towards = GeoMath.normalizedDegrees(windFromDirection + 180)
        let angle = GeoMath.angleDifference(shotBearing, towards).radians
        along = windSpeed * cos(angle)
        across = windSpeed * sin(angle)
    }

    public var description: String {
        let strong = max(abs(along), abs(across))
        if strong < 5 { return "Calm" }
        if abs(along) >= abs(across) { return along > 0 ? "Downwind" : "Into the wind" }
        return across > 0 ? "Left to right" : "Right to left"
    }

    /// Rough "plays like" adjustment: about 1% of distance per km/h of head/tail wind,
    /// with headwinds hurting more than tailwinds help.
    public func playsLike(distance: Double) -> Double {
        let factor = along < 0 ? 0.01 : 0.005
        return distance * (1 - along * factor)
    }
}

/// Open-Meteo forecast client (https://open-meteo.com): free, no API key, CC BY 4.0.
public struct OpenMeteoClient: Sendable {
    public static let attribution = "Weather data by Open-Meteo.com (CC BY 4.0)"
    public static let defaultBaseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!

    let baseURL: URL
    let transport: HTTPTransport

    public init(baseURL: URL = OpenMeteoClient.defaultBaseURL, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func forecast(at point: GeoPoint, days: Int = 3) async throws -> WeatherReport {
        let url = baseURL.appendingQuery([
            URLQueryItem(name: "latitude", value: String(format: "%.4f", point.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", point.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days)),
        ])
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let data = try await transport.data(for: request)
        return try Self.parse(data, location: point)
    }

    // MARK: - Parsing

    struct Response: Decodable {
        var utc_offset_seconds: Int?
        var timezone: String?
        var current: Current
        var hourly: Hourly?
        var daily: Daily?

        struct Current: Decodable {
            var time: String
            var temperature_2m: Double
            var apparent_temperature: Double?
            var relative_humidity_2m: Double?
            var is_day: Int?
            var precipitation: Double?
            var weather_code: Int?
            var wind_speed_10m: Double?
            var wind_direction_10m: Double?
            var wind_gusts_10m: Double?
        }

        struct Hourly: Decodable {
            var time: [String]
            var temperature_2m: [Double?]?
            var precipitation_probability: [Double?]?
            var weather_code: [Int?]?
            var wind_speed_10m: [Double?]?
            var wind_direction_10m: [Double?]?
        }

        struct Daily: Decodable {
            var time: [String]
            var weather_code: [Int?]?
            var temperature_2m_max: [Double?]?
            var temperature_2m_min: [Double?]?
            var precipitation_probability_max: [Double?]?
            var wind_speed_10m_max: [Double?]?
            var sunrise: [String?]?
            var sunset: [String?]?
        }
    }

    public static func parse(_ data: Data, location: GeoPoint, fetchedAt: Date = Date()) throws -> WeatherReport {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
        let offset = response.utc_offset_seconds ?? 0
        func date(_ string: String?) -> Date? { string.flatMap { parseLocalTime($0, utcOffset: offset) } }
        func value<T>(_ array: [T?]?, _ i: Int) -> T? {
            guard let array, i < array.count else { return nil }
            return array[i]
        }

        let c = response.current
        let current = CurrentWeather(
            time: date(c.time) ?? fetchedAt,
            temperature: c.temperature_2m,
            apparentTemperature: c.apparent_temperature,
            humidity: c.relative_humidity_2m,
            precipitation: c.precipitation ?? 0,
            weatherCode: c.weather_code ?? 0,
            windSpeed: c.wind_speed_10m ?? 0,
            windGusts: c.wind_gusts_10m,
            windDirection: c.wind_direction_10m ?? 0,
            isDay: (c.is_day ?? 1) == 1
        )

        var hourly: [HourlyWeather] = []
        if let h = response.hourly {
            for (i, t) in h.time.enumerated() {
                guard let time = date(t), let temp = value(h.temperature_2m, i) else { continue }
                hourly.append(HourlyWeather(
                    time: time, temperature: temp,
                    precipitationProbability: value(h.precipitation_probability, i),
                    weatherCode: value(h.weather_code, i) ?? 0,
                    windSpeed: value(h.wind_speed_10m, i) ?? 0,
                    windDirection: value(h.wind_direction_10m, i) ?? 0
                ))
            }
        }

        var daily: [DailyWeather] = []
        if let d = response.daily {
            for (i, t) in d.time.enumerated() {
                guard let day = date(t), let high = value(d.temperature_2m_max, i), let low = value(d.temperature_2m_min, i) else { continue }
                daily.append(DailyWeather(
                    date: day, high: high, low: low,
                    precipitationProbability: value(d.precipitation_probability_max, i),
                    weatherCode: value(d.weather_code, i) ?? 0,
                    maxWind: value(d.wind_speed_10m_max, i),
                    sunrise: date(value(d.sunrise, i)),
                    sunset: date(value(d.sunset, i))
                ))
            }
        }

        return WeatherReport(location: location, timezone: response.timezone, current: current, hourly: hourly, daily: daily, fetchedAt: fetchedAt)
    }

    /// Open-Meteo returns local times without a zone ("2026-10-29T09:00" or "2026-10-29").
    static func parseLocalTime(_ string: String, utcOffset: Int) -> Date? {
        let parts = string.split(separator: "T")
        let dateParts = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard dateParts.count == 3 else { return nil }
        var hour = 0, minute = 0
        if parts.count > 1 {
            let timeParts = parts[1].split(separator: ":").compactMap { Int($0) }
            hour = timeParts.first ?? 0
            minute = timeParts.count > 1 ? timeParts[1] : 0
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffset) ?? TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: dateParts[0], month: dateParts[1], day: dateParts[2], hour: hour, minute: minute))
    }
}
