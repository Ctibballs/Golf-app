import Foundation

/// Measurement system for display. Everything is stored in SI (metres, °C, km/h)
/// and converted only when shown. Metric is the default.
public enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric
    case imperial

    public static let `default`: UnitSystem = .metric

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    /// Unit label for on-course distances (metres or yards).
    public var distanceUnit: String { self == .metric ? "m" : "yd" }

    /// Unit label for short distances such as putts (metres or feet).
    public var shortDistanceUnit: String { self == .metric ? "m" : "ft" }

    public var temperatureUnit: String { self == .metric ? "°C" : "°F" }

    public var speedUnit: String { self == .metric ? "km/h" : "mph" }
}

public enum UnitConversion {
    public static let metresPerYard = 0.9144
    public static let metresPerFoot = 0.3048
    public static let kilometresPerMile = 1.609344
    public static let millimetresPerInch = 25.4

    public static func yards(fromMetres metres: Double) -> Double { metres / metresPerYard }
    public static func metres(fromYards yards: Double) -> Double { yards * metresPerYard }
    public static func feet(fromMetres metres: Double) -> Double { metres / metresPerFoot }
    public static func fahrenheit(fromCelsius c: Double) -> Double { c * 9 / 5 + 32 }
    public static func mph(fromKmh kmh: Double) -> Double { kmh / kilometresPerMile }
    public static func inches(fromMillimetres mm: Double) -> Double { mm / millimetresPerInch }
}

/// Formats SI values for display in the chosen unit system.
public struct UnitFormatter: Sendable, Equatable {
    public var system: UnitSystem

    public init(system: UnitSystem = .default) {
        self.system = system
    }

    /// Converts metres to the display distance unit (m or yd).
    public func distanceValue(_ metres: Double) -> Double {
        system == .metric ? metres : UnitConversion.yards(fromMetres: metres)
    }

    /// Converts a display distance (m or yd) back to metres.
    public func metres(fromDisplay value: Double) -> Double {
        system == .metric ? value : UnitConversion.metres(fromYards: value)
    }

    /// "152 m" / "166 yd"
    public func distance(_ metres: Double) -> String {
        "\(Int(distanceValue(metres).rounded())) \(system.distanceUnit)"
    }

    /// Distance number only, rounded: "152"
    public func distanceNumber(_ metres: Double) -> String {
        "\(Int(distanceValue(metres).rounded()))"
    }

    /// Putt-length style: "4.2 m" / "14 ft"
    public func shortDistance(_ metres: Double) -> String {
        switch system {
        case .metric:
            return metres < 10 ? String(format: "%.1f m", metres) : "\(Int(metres.rounded())) m"
        case .imperial:
            return "\(Int(UnitConversion.feet(fromMetres: metres).rounded())) ft"
        }
    }

    /// Long distances such as total course length: "6,012 m" / "6,575 yd"
    public func courseLength(_ metres: Double) -> String {
        "\(Self.grouped(Int(distanceValue(metres).rounded()))) \(system.distanceUnit)"
    }

    public func temperatureValue(_ celsius: Double) -> Double {
        system == .metric ? celsius : UnitConversion.fahrenheit(fromCelsius: celsius)
    }

    /// "18°" (unit implied) or with unit "18°C".
    public func temperature(_ celsius: Double, includeUnit: Bool = false) -> String {
        let value = Int(temperatureValue(celsius).rounded())
        return includeUnit ? "\(value)\(system.temperatureUnit)" : "\(value)°"
    }

    public func speedValue(_ kmh: Double) -> Double {
        system == .metric ? kmh : UnitConversion.mph(fromKmh: kmh)
    }

    /// "14 km/h" / "9 mph"
    public func windSpeed(_ kmh: Double) -> String {
        "\(Int(speedValue(kmh).rounded())) \(system.speedUnit)"
    }

    /// "2.1 mm" / "0.08 in"
    public func precipitation(_ millimetres: Double) -> String {
        switch system {
        case .metric: return String(format: "%.1f mm", millimetres)
        case .imperial: return String(format: "%.2f in", UnitConversion.inches(fromMillimetres: millimetres))
        }
    }

    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (value < 0 ? "-" : "") + String(out.reversed())
    }
}
