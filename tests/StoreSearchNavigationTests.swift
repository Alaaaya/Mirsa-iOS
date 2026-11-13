import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class StoreSearchNavigationTests: XCTestCase {
    func testSearchDetailResultsMain() {
        var nav = StoreSearchNavigation()
        XCTAssertFalse(nav.showsBack)
        nav.term = "tiktok"; nav.resultCount = 5; nav.searched = true
        XCTAssertTrue(nav.showsBack)
        nav.openDetail()
        XCTAssertFalse(nav.showsBack)
        nav.backFromDetail()
        XCTAssertTrue(nav.showsBack)
        XCTAssertEqual(nav.resultCount, 5)
        XCTAssertEqual(nav.term, "tiktok")
        nav.returnToMain()
        XCTAssertFalse(nav.showsBack)
        XCTAssertEqual(nav, StoreSearchNavigation())
    }

    func testClearSearchReturnsMain() {
        var nav = StoreSearchNavigation(term: "x", resultCount: 2, searched: true, genreActive: true, detailOpen: false)
        nav.returnToMain()
        XCTAssertEqual(nav, StoreSearchNavigation())
    }

    func testBackReachableForEmptyAndFailedSearch() {
        XCTAssertTrue(StoreSearchNavigation(term: "zzz", resultCount: 0, searched: true).showsBack)
        XCTAssertTrue(StoreSearchNavigation(term: "zzz", resultCount: 0, searched: false).showsBack)
        XCTAssertFalse(StoreSearchNavigation(term: "  ", resultCount: 0, searched: false).showsBack)
    }
}
