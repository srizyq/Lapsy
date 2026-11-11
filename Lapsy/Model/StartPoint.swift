import CoreLocation

struct StartPoint: Equatable {
    var name: String
    var coordinate: CLLocationCoordinate2D

    static func == (a: StartPoint, b: StartPoint) -> Bool {
        a.name == b.name
            && a.coordinate.latitude == b.coordinate.latitude
            && a.coordinate.longitude == b.coordinate.longitude
    }

    /// Used until the phone gives us a location or the user searches for one.
    static let fallback = StartPoint(
        name: "San Francisco",
        coordinate: CLLocationCoordinate2D(latitude: 37.8030, longitude: -122.4375)
    )
}
