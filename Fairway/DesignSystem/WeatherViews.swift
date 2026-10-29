import SwiftUI
import GolfKit

/// Current conditions, a playability verdict and the next few hours, laid out flat.
struct WeatherPanel: View {
    let report: WeatherReport
    let units: UnitFormatter
    /// Bearing of the current hole, to describe the wind relative to play.
    var holeBearing: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(units.temperature(report.current.temperature))
                        .font(.display(52, weight: .regular))
                        .contentTransition(.numericText(value: report.current.temperature))
                    Text(report.current.condition.description)
                        .font(.subheadline.weight(.medium))
                    if let feels = report.current.apparentTemperature {
                        Text("Feels like \(units.temperature(feels))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: report.current.condition.symbolName(isDay: report.current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 38, weight: .light))
                    .symbolEffect(.bounce, value: report.fetchedAt)
                    .padding(.top, 8)
            }

            MetricGrid(items: metrics, columns: 3, compact: true)
                .overlay(alignment: .top) { Hairline() }

            let hours = report.upcomingHours(count: 6)
            if !hours.isEmpty {
                HStack(spacing: 0) {
                    ForEach(hours) { hour in
                        VStack(spacing: 6) {
                            Text(hour.time, format: .dateTime.hour())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: hour.condition.symbolName())
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 20)
                            Text(units.temperature(hour.temperature))
                                .font(.figure(14, weight: .medium))
                            Text(rainText(hour.precipitationProbability))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.water)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Hairline() }
            }
        }
    }

    private var metrics: [MetricItem] {
        let current = report.current
        let windDetail: String
        if let holeBearing {
            windDetail = WindEffect(windSpeed: current.windSpeed, windFromDirection: current.windDirection, shotBearing: holeBearing).description
        } else if let gusts = current.windGusts, gusts > current.windSpeed + 5 {
            windDetail = "\(Compass.point(current.windDirection)) · gusts \(units.windSpeed(gusts))"
        } else {
            windDetail = "From the \(Compass.point(current.windDirection))"
        }
        let rain = report.upcomingHours(count: 3).compactMap(\.precipitationProbability).max()
        let playability = report.playability
        return [
            MetricItem(label: "Wind", value: units.windSpeed(current.windSpeed), detail: windDetail),
            MetricItem(label: "Rain", value: rain.map { "\(Int($0))%" } ?? "—", detail: "Next 3 hours"),
            MetricItem(label: "Playability", value: "\(playability.score)", detail: playability.headline, tint: PlayabilityGauge.color(playability.score)),
        ]
    }

    private func rainText(_ probability: Double?) -> String {
        guard let probability, probability >= 20 else { return " " }
        return "\(Int(probability))%"
    }
}

enum Compass {
    static func point(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int((normalized + 22.5) / 45) % 8]
    }
}

/// Wind speed with an arrow showing where it blows, relative to the hole when known.
struct WindBadge: View {
    let speed: Double
    var gusts: Double?
    let fromDirection: Double
    let units: UnitFormatter
    var holeBearing: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.fill")
                .imageScale(.small)
                .rotationEffect(.degrees(fromDirection + 180 - (holeBearing ?? 0)))
                .animation(.snappySpring, value: fromDirection)
            VStack(alignment: .leading, spacing: 0) {
                Text(units.windSpeed(speed)).font(.subheadline.weight(.semibold)).monospacedDigit()
                if let holeBearing {
                    Text(WindEffect(windSpeed: speed, windFromDirection: fromDirection, shotBearing: holeBearing).description)
                        .font(.caption2).opacity(0.8)
                } else if let gusts, gusts > speed + 5 {
                    Text("Gusts \(units.windSpeed(gusts))").font(.caption2).opacity(0.8)
                }
            }
        }
    }
}

/// A thin ring showing the playability score.
struct PlayabilityGauge: View {
    let playability: Playability

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(playability.score) / 100)
                    .stroke(Self.color(playability.score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(playability.score)").font(.figure(10, weight: .semibold))
            }
            .frame(width: 30, height: 30)
            Text(playability.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    static func color(_ score: Int) -> Color {
        switch score {
        case 75...: return Theme.fairway
        case 45..<75: return Theme.gold
        default: return Theme.flag
        }
    }
}

/// Compact inline conditions for headers: "☀️ 18° · 12 km/h ↗".
struct WeatherChip: View {
    let report: WeatherReport
    let units: UnitFormatter
    var holeBearing: Double?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: report.current.condition.symbolName(isDay: report.current.isDay))
                .symbolRenderingMode(.multicolor)
            Text(units.temperature(report.current.temperature))
            Text("·").foregroundStyle(.tertiary)
            Text(units.windSpeed(report.current.windSpeed))
            if let holeBearing {
                Image(systemName: "location.north.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(report.current.windDirection + 180 - holeBearing))
            }
        }
        .font(.footnote.weight(.medium))
        .monospacedDigit()
    }
}
