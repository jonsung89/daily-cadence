import Foundation
import OSLog
import Supabase

/// Phase F.1.2.daymarks — Supabase round-trip for the per-day emoji
/// markers shown on the Today week strip. One emoji per (user, day);
/// upsert on set, delete on clear. Bulk fetch on launch is small (most
/// users have <50 marked days), so no pagination needed.
final class DayMarkRepository {
    static let shared = DayMarkRepository()

    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "DayMarkRepository")

    private init() {}

    /// Loads every emoji mark for the user. Returns a `[startOfDay: emoji]`
    /// dict keyed by `Calendar.current.startOfDay(for: row.day)` so callers
    /// can match against `TimelineStore.selectedDate` / week-strip days
    /// without an extra normalization pass. Postgres `date` columns
    /// serialize as `YYYY-MM-DD` strings; we decode as String and parse
    /// in the user's local calendar so the wire format stays TZ-agnostic.
    func fetchAll(userId: UUID) async throws -> [Date: String] {
        let rows: [DayMarkRow] = try await AppSupabase.client
            .from("day_marks")
            .select("day, emoji")
            .eq("user_id", value: userId)
            .execute()
            .value
        var out: [Date: String] = [:]
        out.reserveCapacity(rows.count)
        for row in rows {
            guard let key = parseDayString(row.day) else {
                log.error("Skipping unparseable day mark: \(row.day)")
                continue
            }
            out[key] = row.emoji
        }
        log.info("Fetched \(rows.count) day marks")
        return out
    }

    /// Parses a `YYYY-MM-DD` Postgres `date` payload into the local-
    /// calendar `startOfDay` Date. Returns `nil` for anything malformed.
    private func parseDayString(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    /// Upsert: set `emoji` for `(user_id, day)`. Day is encoded as the
    /// SQL `date` type so timezone wobble doesn't shift the marker — the
    /// user's calendar day is what matters, not a precise timestamp.
    func setMark(userId: UUID, day: Date, emoji: String) async throws {
        let payload = DayMarkUpsert(
            user_id: userId,
            day: dayString(from: day),
            emoji: emoji
        )
        try await AppSupabase.client
            .from("day_marks")
            .upsert(payload, onConflict: "user_id,day")
            .execute()
        log.info("Upserted day mark: day=\(self.dayString(from: day)) emoji=\(emoji)")
    }

    /// Removes the mark for `(user_id, day)`. No-op when no row exists.
    func clearMark(userId: UUID, day: Date) async throws {
        try await AppSupabase.client
            .from("day_marks")
            .delete()
            .eq("user_id", value: userId)
            .eq("day", value: dayString(from: day))
            .execute()
        log.info("Cleared day mark: day=\(self.dayString(from: day))")
    }

    /// Postgres `date` wants a `YYYY-MM-DD` string in the user's local
    /// timezone — we want "the calendar day the user perceives," not a
    /// UTC-shifted value. ISO 8601 with date-only formatting gives that
    /// directly, locale-independent.
    private func dayString(from day: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}

// MARK: - Wire types

private struct DayMarkRow: Decodable {
    let day: String
    let emoji: String
}

private struct DayMarkUpsert: Encodable {
    let user_id: UUID
    let day: String
    let emoji: String
}
