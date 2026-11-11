import CoreLocation

/// One point on the route with its distance along the route and elevation.
struct ProfilePoint: Identifiable {
    let id: Int
    let km: Double
    let elevation: Double
    let coordinate: CLLocationCoordinate2D
    /// Slope here as a percentage, positive uphill (smoothed over about 150 m).
    let grade: Double
    /// ORS surface code at this point, nil if unknown.
    let surfaceCode: Int?

    /// Plain-words slope, e.g. "Uphill 3%".
    var gradeText: String {
        let rounded = Int(abs(grade).rounded())
        if rounded == 0 { return "Flat" }
        return grade > 0 ? "Uphill \(rounded)%" : "Downhill \(rounded)%"
    }

    var surfaceText: String {
        guard let code = surfaceCode else { return "Surface unknown" }
        return SurfaceMix.name(for: code)
    }
}

extension SurfaceMix {
    /// Plain names for ORS surface codes.
    static func name(for code: Int) -> String {
        switch code {
        case 1: "Paved"
        case 2: "Unpaved"
        case 3: "Asphalt"
        case 4: "Concrete"
        case 5: "Cobblestone"
        case 6: "Metal"
        case 7: "Wood"
        case 8, 9, 10: "Gravel"
        case 11: "Dirt"
        case 12: "Ground"
        case 13: "Ice"
        case 14: "Paving stones"
        case 15: "Sand"
        case 16: "Woodchips"
        case 17, 18: "Grass"
        default: "Surface unknown"
        }
    }
}

extension GeneratedRoute {
    /// Route points with cumulative distance, thinned to about 120 for charting.
    var profilePoints: [ProfilePoint] {
        // Distance and elevation for every vertex first, so slope can look around each point.
        var meters: [Double] = []
        var total = 0.0
        var previous: CLLocation?
        for c in coordinates {
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if let previous { total += here.distance(from: previous) }
            previous = here
            meters.append(total)
        }
        let elevation = { (i: Int) -> Double in i < self.elevations.count ? self.elevations[i] : 0 }

        // Slope over a window of about 75 m either side; single-point slopes are too noisy.
        let window = 75.0
        func grade(at i: Int) -> Double {
            var a = i, b = i
            while a > 0, meters[i] - meters[a] < window { a -= 1 }
            while b < meters.count - 1, meters[b] - meters[i] < window { b += 1 }
            let run = meters[b] - meters[a]
            guard run > 20 else { return 0 }
            return ((elevation(b) - elevation(a)) / run * 100).clamped(to: -30...30)
        }

        let all = coordinates.indices.map { i in
            ProfilePoint(
                id: i,
                km: meters[i] / 1000,
                elevation: elevation(i),
                coordinate: coordinates[i],
                grade: grade(at: i),
                surfaceCode: i < surfaceCodes.count ? surfaceCodes[i] : nil
            )
        }
        let step = max(1, all.count / 120)
        return all.enumerated()
            .filter { $0.offset % step == 0 || $0.offset == all.count - 1 }
            .map(\.element)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
