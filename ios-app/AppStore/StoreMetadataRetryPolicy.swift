import Foundation

/// Version-name lookups: a timeout or transport failure is retried a bounded number of times before a row
/// is shown as unavailable. Only an explicit server answer is terminal immediately.
enum StoreMetadataRetryPolicy {
    static let maxAttempts = 4
    static func shouldRetry(attempt: Int) -> Bool { attempt < maxAttempts }
    static func delay(attempt: Int) -> TimeInterval { min(2.0 * Double(max(1, attempt)), 8.0) }

    /// New visibility/reopen: forget attempts and the terminal state of exhausted rows so they load again.
    static func resetExhausted(key: String, ids: [String], attempts: inout [String: Int], unavailable: (String) -> Bool, clear: (String) -> Void) {
        for id in ids where unavailable(id) { clear(id); attempts[key + "|" + id] = nil }
    }
}
