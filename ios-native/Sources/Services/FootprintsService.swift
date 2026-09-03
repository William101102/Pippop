import CoreLocation
import Foundation
import Supabase

/// One place you visit often, with a dwell-time estimate — the
/// `my_frequent_places()` RPC's row shape.
struct FrequentPlace: Decodable, Sendable {
    let cellLat: Int64
    let cellLng: Int64
    let lat: Double
    let lng: Double
    let visits: Int
    let minutes: Double
    let lastSeen: Date

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

/// Footprints: your own location-history summary. Both RPCs are
/// `security definer` and scoped to `auth.uid()` server-side, so there's
/// nothing to pass but a day window — see `my_heatmap`/`my_frequent_places`
/// in `backend/supabase/setup.sql`.
enum FootprintsService {
    static func loadFrequentPlaces(days: Int = 30) async throws -> [FrequentPlace] {
        try await Backend.client
            .rpc("my_frequent_places", params: ["p_days": days])
            .execute()
            .value
    }

    /// One heatmap grid cell — same shape the web app's `loadHeatmap` reads
    /// from the `my_heatmap` RPC (see backend/supabase/setup.sql).
    struct HeatCell: Decodable, Sendable {
        let lat: Double
        let lng: Double
        let hits: Int
    }

    static func loadHeatmap(days: Int = 30) async throws -> [HeatCell] {
        try await Backend.client
            .rpc("my_heatmap", params: ["p_days": days])
            .execute()
            .value
    }

    /// Human-readable duration, matching the web app's `humanMinutes`.
    static func humanMinutes(_ minutes: Double) -> String {
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let hours = minutes / 60
        if hours < 24 { return String(format: "%.\(hours < 10 ? 1 : 0)f hr", hours) }
        return String(format: "%.1f d", hours / 24)
    }
}
