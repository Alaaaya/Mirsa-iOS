import Foundation

/// Pure navigation state for the Store search tab (both themes). Detail -> results -> main list.
struct StoreSearchNavigation: Equatable {
    var term = ""
    var resultCount = 0
    var searched = false
    var genreActive = false
    var detailOpen = false

    /// Back is always offered on the results level: results, empty, failed (term typed) or loading a search.
    var showsBack: Bool {
        !detailOpen && (resultCount > 0 || searched || !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    mutating func openDetail() { detailOpen = true }
    mutating func backFromDetail() { detailOpen = false }
    /// Returns to the main store list without any app restart. Used by the back button and by clearing the search.
    mutating func returnToMain() {
        term = ""; resultCount = 0; searched = false; genreActive = false; detailOpen = false
    }
}
