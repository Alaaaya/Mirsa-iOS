import Foundation

/// Presentation only. Original purchase IDs and timestamps are never rewritten.
enum StorePurchaseGroups {
    struct Group: Identifiable {
        let month: Date?
        let items: [MirsaStorePurchase]
        var id: Date? { month }
    }

    static func validDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite,
              date >= .distantPast, date <= .distantFuture else { return nil }
        return date
    }

    static func make(_ items: [MirsaStorePurchase], calendar: Calendar = .current) -> [Group] {
        // Explicit source-index tie break keeps equal/missing-date rows stable.
        let sorted = items.enumerated().sorted { lhs, rhs in
            let a = validDate(lhs.element.date)
            let b = validDate(rhs.element.date)
            if a == b { return lhs.offset < rhs.offset }
            guard let a else { return false }
            guard let b else { return true }
            return a > b
        }
        var groups: [Group] = []
        var rows: [MirsaStorePurchase] = []
        var month: Date?
        for entry in sorted {
            let next = validDate(entry.element.date).flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
            if !rows.isEmpty, next != month {
                groups.append(Group(month: month, items: rows))
                rows = []
            }
            month = next
            rows.append(entry.element)
        }
        if !rows.isEmpty { groups.append(Group(month: month, items: rows)) }
        return groups
    }

    static func title(_ month: Date, locale: Locale, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month)
    }
}
