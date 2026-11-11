import CoreLocation

/// Google-style encoded polyline (1e-5 degrees, about 1 m). Turns a long list of
/// coordinates into one short string for disk and for the database.
enum Polyline {
    static func encode(_ coordinates: [CLLocationCoordinate2D]) -> String {
        var out = ""
        var lastLat = 0, lastLon = 0
        for c in coordinates {
            let lat = Int((c.latitude * 1e5).rounded())
            let lon = Int((c.longitude * 1e5).rounded())
            out += chunk(lat - lastLat) + chunk(lon - lastLon)
            lastLat = lat
            lastLon = lon
        }
        return out
    }

    static func decode(_ text: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(text.utf8)
        var index = 0, lat = 0, lon = 0
        var out: [CLLocationCoordinate2D] = []

        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }

        while let dLat = next(), let dLon = next() {
            lat += dLat
            lon += dLon
            out.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return out
    }

    private static func chunk(_ value: Int) -> String {
        var n = value < 0 ? ~(value << 1) : (value << 1)
        var s = ""
        while n >= 0x20 {
            s.append(Character(UnicodeScalar(UInt8((0x20 | (n & 0x1f)) + 63))))
            n >>= 5
        }
        s.append(Character(UnicodeScalar(UInt8(n + 63))))
        return s
    }
}
