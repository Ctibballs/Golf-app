import Foundation

/// A WGS84 coordinate. GolfKit stays free of CoreLocation so it can be tested anywhere;
/// the app converts to and from `CLLocationCoordinate2D` at the edges.
public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum GeoMath {
    /// Mean Earth radius in metres (IUGG).
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres (haversine).
    public static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLat = (b.latitude - a.latitude).radians
        let dLon = (b.longitude - a.longitude).radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b` in degrees clockwise from true north (0..<360).
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLon = (b.longitude - a.longitude).radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalizedDegrees(atan2(y, x).degrees)
    }

    /// The point reached by travelling `distance` metres from `origin` on `bearing` degrees.
    public static func destination(from origin: GeoPoint, bearing: Double, distance: Double) -> GeoPoint {
        let delta = distance / earthRadius
        let theta = bearing.radians
        let lat1 = origin.latitude.radians, lon1 = origin.longitude.radians
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(delta) * cos(lat1), cos(delta) - sin(lat1) * sin(lat2))
        return GeoPoint(latitude: lat2.degrees, longitude: normalizedLongitude(lon2.degrees))
    }

    /// Linear interpolation. Accurate enough over golf-hole distances.
    public static func interpolate(_ a: GeoPoint, _ b: GeoPoint, fraction: Double) -> GeoPoint {
        let t = max(0, min(1, fraction))
        return GeoPoint(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Total length of a polyline in metres.
    public static func length(of path: [GeoPoint]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// The point `distance` metres along a polyline (clamped to its ends).
    public static func point(along path: [GeoPoint], distance target: Double) -> GeoPoint? {
        guard var previous = path.first else { return nil }
        var travelled = 0.0
        for next in path.dropFirst() {
            let segment = distance(previous, next)
            if travelled + segment >= target, segment > 0 {
                return interpolate(previous, next, fraction: (target - travelled) / segment)
            }
            travelled += segment
            previous = next
        }
        return previous
    }

    /// Area-weighted centroid of a polygon, falling back to the vertex average for degenerate shapes.
    public static func centroid(of polygon: [GeoPoint]) -> GeoPoint? {
        guard !polygon.isEmpty else { return nil }
        let ring = closedRing(polygon)
        var area = 0.0, cx = 0.0, cy = 0.0
        for (p, q) in zip(ring, ring.dropFirst()) {
            let cross = p.longitude * q.latitude - q.longitude * p.latitude
            area += cross
            cx += (p.longitude + q.longitude) * cross
            cy += (p.latitude + q.latitude) * cross
        }
        if abs(area) < 1e-14 {
            let n = Double(polygon.count)
            return GeoPoint(
                latitude: polygon.map(\.latitude).reduce(0, +) / n,
                longitude: polygon.map(\.longitude).reduce(0, +) / n
            )
        }
        area *= 0.5
        return GeoPoint(latitude: cy / (6 * area), longitude: cx / (6 * area))
    }

    /// Ray-casting point-in-polygon test.
    public static func contains(_ polygon: [GeoPoint], _ point: GeoPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i], pj = polygon[j]
            if (pi.latitude > point.latitude) != (pj.latitude > point.latitude) {
                let x = (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) / (pj.latitude - pi.latitude) + pi.longitude
                if point.longitude < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Shortest distance in metres from `point` to the segment `a`–`b`, using a local flat projection.
    public static func distance(from point: GeoPoint, toSegment a: GeoPoint, _ b: GeoPoint) -> Double {
        let origin = a
        let p = project(point, origin: origin), q = project(b, origin: origin)
        let lengthSquared = q.x * q.x + q.y * q.y
        guard lengthSquared > 0 else { return hypot(p.x, p.y) }
        let t = max(0, min(1, (p.x * q.x + p.y * q.y) / lengthSquared))
        return hypot(p.x - t * q.x, p.y - t * q.y)
    }

    /// Shortest distance from a point to any segment of a polyline.
    public static func distance(from point: GeoPoint, toPath path: [GeoPoint]) -> Double {
        guard let first = path.first else { return .infinity }
        guard path.count > 1 else { return distance(point, first) }
        return zip(path, path.dropFirst()).map { distance(from: point, toSegment: $0.0, $0.1) }.min() ?? .infinity
    }

    /// Bounding box of a set of points.
    public static func bounds(of points: [GeoPoint]) -> GeoBounds? {
        guard let first = points.first else { return nil }
        var b = GeoBounds(minLatitude: first.latitude, maxLatitude: first.latitude,
                          minLongitude: first.longitude, maxLongitude: first.longitude)
        for p in points.dropFirst() {
            b.minLatitude = min(b.minLatitude, p.latitude)
            b.maxLatitude = max(b.maxLatitude, p.latitude)
            b.minLongitude = min(b.minLongitude, p.longitude)
            b.maxLongitude = max(b.maxLongitude, p.longitude)
        }
        return b
    }

    /// Signed angle difference `b - a` in degrees, normalised to -180...180.
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    public static func normalizedDegrees(_ value: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    // MARK: - Helpers

    /// Equirectangular projection to metres around `origin`; fine for distances under a few km.
    static func project(_ point: GeoPoint, origin: GeoPoint) -> (x: Double, y: Double) {
        let x = (point.longitude - origin.longitude).radians * cos(origin.latitude.radians) * earthRadius
        let y = (point.latitude - origin.latitude).radians * earthRadius
        return (x, y)
    }

    static func closedRing(_ polygon: [GeoPoint]) -> [GeoPoint] {
        guard let first = polygon.first, polygon.last != first else { return polygon }
        return polygon + [first]
    }

    static func normalizedLongitude(_ value: Double) -> Double {
        var v = value
        while v > 180 { v -= 360 }
        while v < -180 { v += 360 }
        return v
    }
}

public struct GeoBounds: Codable, Hashable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public var center: GeoPoint {
        GeoPoint(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    public var latitudeSpan: Double { maxLatitude - minLatitude }
    public var longitudeSpan: Double { maxLongitude - minLongitude }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
