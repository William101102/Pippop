import Foundation
import Supabase

/// Single shared Supabase client.
///
/// Keys come from `Secrets.xcconfig` (gitignored) -> Info.plist -> here, so no
/// credential is ever committed. Only the **anon** key belongs in the app; a
/// service-role key in a shipped binary is a full database compromise.
enum Backend {
    static let client: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty
        else {
            fatalError("""
                Missing SUPABASE_URL / SUPABASE_ANON_KEY.
                Copy Sources/Config/Secrets.example.xcconfig to Secrets.xcconfig and fill it in.
                """)
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: .init(
                db: .init(encoder: encoder, decoder: decoder)
            )
        )
    }()

    /// Postgres is snake_case, Swift is camelCase — convert once, centrally,
    /// so no model needs hand-written CodingKeys.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = Formatters.isoWithFraction.date(from: raw) { return date }
            if let date = Formatters.iso.date(from: raw) { return date }
            // Not every date column is a timestamp. Postgres `date` columns —
            // `friendships.last_interaction_on` is one — come back as a bare
            // "2026-09-05" with no time and no zone, which neither formatter
            // above accepts. That threw right out of `FriendsService.load`
            // and emptied the entire friends list, and only from the moment
            // the column stopped being null: the first wave or throw sets it
            // via the streak trigger, so the list worked until you actually
            // had a friend to interact with.
            if let date = Formatters.dateOnly.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised timestamp: \(raw)"
            )
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Formatters.isoWithFraction.string(from: date))
        }
        return e
    }()
}

enum Formatters {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Postgres `date` columns: "2026-09-05", no time, no zone.
    ///
    /// Parsed as **UTC midnight** on purpose. The server writes these as
    /// `(now() at time zone 'utc')::date` and `StreakInfo.compute` compares
    /// them with a UTC calendar, so UTC midnight is the value that round-trips
    /// to the same calendar day on both sides. Parsing in the device's own
    /// zone would shift the day for anyone west of Greenwich and quietly cost
    /// them a streak day.
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
