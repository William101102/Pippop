import CoreLocation
import Foundation
import Supabase

enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case cafe, food, park, gym, shop, home, work, other

    var label: String {
        switch self {
        case .cafe: "Cafe"
        case .food: "Food"
        case .park: "Park"
        case .gym: "Gym"
        case .shop: "Shopping"
        case .home: "Home"
        case .work: "Work"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .cafe: "☕️"
        case .food: "🍜"
        case .park: "🌳"
        case .gym: "🏋️"
        case .shop: "🛍️"
        case .home: "🏠"
        case .work: "💼"
        case .other: "📍"
        }
    }
}

enum VisitVisibility: String, Codable, CaseIterable, Sendable {
    case friends, `private`

    var label: String {
        self == .friends ? "Friends can see" : "Only me"
    }

    var detail: String {
        self == .friends ? "Friends can see this check-in nearby" : "Only shows up in your own footprints"
    }
}

struct CheckInPlace: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var category: PlaceCategory
    var address: String?
    var lat: Double
    var lng: Double
    var createdBy: UUID?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

struct NearbyPlace: Identifiable, Hashable, Sendable {
    let place: CheckInPlace
    let distanceMeters: Double
    var id: UUID { place.id }
}

enum CheckInsService {
    /// Same free, no-key Nominatim endpoint the web app uses — a rough name
    /// suggestion for the check-in field, not billed or rate-limit-managed
    /// beyond "don't call it in a tight loop".
    static func reverseGeocode(lat: Double, lng: Double) async -> (name: String?, address: String?) {
        guard let url = URL(string: "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&addressdetails=1&lat=\(lat)&lon=\(lng)") else {
            return (nil, nil)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, nil) }

        let address = json["address"] as? [String: Any]
        let name = (json["name"] as? String)
            ?? (address?["amenity"] as? String)
            ?? (address?["shop"] as? String)
            ?? (address?["building"] as? String)
            ?? (address?["road"] as? String)
            ?? (address?["neighbourhood"] as? String)
            ?? (address?["suburb"] as? String)
        return (name, json["display_name"] as? String)
    }

    @discardableResult
    static func checkIn(
        userId: UUID, name: String, category: PlaceCategory, lat: Double, lng: Double,
        address: String?, visibility: VisitVisibility, note: String?
    ) async throws -> CheckInPlace {
        struct NewPlace: Encodable {
            let name: String
            let category: String
            let address: String?
            let lat: Double
            let lng: Double
            let source: String
            let createdBy: UUID
        }
        let place: CheckInPlace = try await Backend.client
            .from("places")
            .insert(NewPlace(
                name: name, category: category.rawValue, address: address,
                lat: lat, lng: lng, source: "user", createdBy: userId
            ))
            .select("id,name,category,address,lat,lng,created_by")
            .single()
            .execute()
            .value

        struct NewVisit: Encodable {
            let userId: UUID
            let placeId: UUID
            let visibility: String
            let note: String?
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await Backend.client
            .from("visits")
            .insert(NewVisit(
                userId: userId, placeId: place.id, visibility: visibility.rawValue,
                note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
            ))
            .execute()

        return place
    }

    /// A bounding-box prefilter (cheap, index-friendly) followed by an exact
    /// great-circle distance check and sort — same two-step approach as the
    /// web app's `loadNearbyPlaces`.
    static func loadNearbyPlaces(lat: Double, lng: Double, radiusKm: Double = 5) async throws -> [NearbyPlace] {
        let degPerKm = 1.0 / 111.0
        let pad = radiusKm * degPerKm
        let lngPad = pad / max(cos(lat * .pi / 180), 0.01)

        let places: [CheckInPlace] = try await Backend.client
            .from("places")
            .select("id,name,category,address,lat,lng,created_by")
            .gte("lat", value: lat - pad)
            .lte("lat", value: lat + pad)
            .gte("lng", value: lng - lngPad)
            .lte("lng", value: lng + lngPad)
            .limit(200)
            .execute()
            .value

        let origin = CLLocation(latitude: lat, longitude: lng)
        return places
            .map { NearbyPlace(place: $0, distanceMeters: origin.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))) }
            .filter { $0.distanceMeters <= radiusKm * 1000 }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }
}
