import SwiftUI
import GolfKit

/// Current conditions, a playability verdict and the next few hours.
struct WeatherCard: View {
    let report: WeatherReport
    let units: UnitFormatter
    /// Bearing of the current hole, to describe the wind relative to play.
    var holeBearing: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(units.temperature(report.current.temperature))
                        .font(.rounded(44, weight: .bold))
                        .contentTransition(.numericText())
                    Text(report.current.condition.description)
                        .font(.subheadline.weight(.semibold))
                    if let feels = report.current.apparentTemperature {
                        Text("Feels like \(units.temperature(feels))")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
                Spacer()
                Image(systemName: report.current.condition.symbolName(isDay: report.current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 46))
                    .symbolEffect(.pulse, options: .speed(0.5))
            }

            HStack(spacing: 10) {
                WindBadge(speed: report.current.windSpeed, gusts: report.current.windGusts, fromDirection: report.current.windDirection, units: units, holeBearing: holeBearing)
                Spacer()
                PlayabilityGauge(playability: report.playability)
            }

            let hours = report.upcomingHours(count: 6)
            if !hours.isEmpty {
                Divider().overlay(.white.opacity(0.3))
                HStack(spacing: 0) {
                    ForEach(hours) { hour in
                        VStack(spacing: 6) {
                            Text(hour.time, format: .dateTime.hour())
                                .font(.caption2.weight(.semibold))
                                .opacity(0.8)
                            Image(systemName: hour.condition.symbolName())
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 20)
                            Text(units.temperature(hour.temperature))
                                .font(.caption.weight(.bold))
                            if let rain = hour.precipitationProbability, rain >= 20 {
                                Text("\(Int(rain))%")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(hex: 0xBFE3FF))
                            } else {
                                Text(" ").font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.water.opacity(0.25), radius: 14, y: 6)
    }

    private var background: LinearGradient {
        let code = report.current.weatherCode
        if !report.current.isDay {
            return LinearGradient(colors: [Color(hex: 0x1D2B64), Color(hex: 0x0F1730)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if code >= 61 {
            return LinearGradient(colors: [Color(hex: 0x5B7083), Color(hex: 0x34495E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if code >= 3 {
            return LinearGradient(colors: [Color(hex: 0x7F9CC0), Color(hex: 0x4F6D9A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return Theme.skyGradient
    }
}

struct WindBadge: View {
    let speed: Double
    var gusts: Double?
    let fromDirection: Double
    let units: UnitFormatter
    var holeBearing: Double?

    var body: some View {
        HStack(spacing: 8) {
            // The arrow points where the wind is blowing to, rotated relative to the hole when known.
            Image(systemName: "location.north.fill")
                .rotationEffect(.degrees(fromDirection + 180 - (holeBearing ?? 0)))
                .animation(.snappySpring, value: fromDirection)
            VStack(alignment: .leading, spacing: 0) {
                Text(units.windSpeed(speed)).font(.subheadline.weight(.bold))
                if let holeBearing {
                    Text(WindEffect(windSpeed: speed, windFromDirection: fromDirection, shotBearing: holeBearing).description)
                        .font(.caption2).opacity(0.85)
                } else if let gusts, gusts > speed + 5 {
                    Text("Gusts \(units.windSpeed(gusts))").font(.caption2).opacity(0.85)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.18), in: Capsule())
    }
}

struct PlayabilityGauge: View {
    let playability: Playability

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(playability.score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(playability.score)").font(.caption2.weight(.heavy))
            }
            .frame(width: 34, height: 34)
            Text(playability.headline)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: 120, alignment: .leading)
        }
    }

    private var color: Color {
        switch playability.score {
        case 75...: return Theme.lime
        case 45..<75: return Theme.gold
        default: return Theme.flag
        }
    }
}

/// Compact chip for headers: "☀️ 18° · 12 km/h".
struct WeatherChip: View {
    let report: WeatherReport
    let units: UnitFormatter
    var holeBearing: Double?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: report.current.condition.symbolName(isDay: report.current.isDay))
                .symbolRenderingMode(.multicolor)
            Text(units.temperature(report.current.temperature))
            Image(systemName: "wind")
            Text(units.windSpeed(report.current.windSpeed))
            if let holeBearing {
                Image(systemName: "location.north.fill")
                    .imageScale(.small)
                    .rotationEffect(.degrees(report.current.windDirection + 180 - holeBearing))
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}
