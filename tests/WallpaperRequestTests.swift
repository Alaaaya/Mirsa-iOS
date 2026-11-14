import XCTest
import UIKit
@testable import Mirsa

@MainActor final class WallpaperRequestTests: XCTestCase {
    override func tearDown() { ForgeQueued.transport = nil; super.tearDown() }

    func testVerbatimAndStableRetryWithoutFalseSuccess() async throws {
        let draft = WallpaperRequestDraft()
        draft.text = "  خلفية .tendies\n keep EVERY word  "
        var bodies: [[String: Any]] = []
        var keys: [String] = []
        ForgeQueued.transport = { body, key in
            bodies.append(body); keys.append(key)
            if bodies.count == 1 { throw URLError(.timedOut) }
            let original = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            return (try JSONSerialization.data(withJSONObject: [
                "saved": true, "status": "manual-queue",
                "threadID": draft.threadID.uuidString.lowercased(),
                "originalID": original, "reviewID": original,
                "replayed": true, "message": "saved"
            ]), 200)
        }
        await draft.submit()
        XCTAssertNil(draft.receipt)
        XCTAssertNotNil(draft.error)
        XCTAssertFalse(draft.canEdit)
        await draft.submit()
        XCTAssertNotNil(draft.receipt)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(bodies[0]["prompt"] as? String, draft.text)
        XCTAssertEqual(bodies[1]["threadID"] as? String, bodies[0]["threadID"] as? String)
    }

    func testGeneratedCodeNeverMeansWallpaperDelivered() async {
        let draft = WallpaperRequestDraft(); draft.text = "Wallpaper"
        ForgeQueued.transport = { _, _ in
            (try JSONSerialization.data(withJSONObject: ["code": "not a wallpaper"]), 200)
        }
        await draft.submit()
        XCTAssertNil(draft.receipt); XCTAssertNotNil(draft.error)
    }

    func testReferenceBudgetAndMetadataNormalization() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 2400)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 2400))
        }
        let jpeg = try XCTUnwrap(WallpaperRequestDraft.photo(try XCTUnwrap(image.pngData())))
        XCTAssertLessThanOrEqual(jpeg.count, 40 * 1024)
        XCTAssertNotNil(UIImage(data: jpeg))
        XCTAssertNil(WallpaperRequestDraft.photo(Data("bad".utf8)))
    }
}
