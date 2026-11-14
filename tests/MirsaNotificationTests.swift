import XCTest
@testable import Mirsa

final class MirsaNotificationTests: XCTestCase {
    func testNumericVersionsAndEqualVersionBuilds() throws {
        func v(_ version: String, _ build: String = "5.94.1") throws -> MirsaNotificationVersion {
            try XCTUnwrap(MirsaNotificationVersion(version, build: build))
        }
        XCTAssertLessThan(try v("2.9"), try v("2.10"))
        XCTAssertLessThan(try v("2.5", "5.9.1"), try v("2.5", "5.10.1"))
        XCTAssertEqual(try v("2.5", "5.94.1"), try v("2.5.0", "5.94.1.0"))
        XCTAssertLessThan(try v("2.4", "999.1"), try v("2.5", "5.94.1"))
        XCTAssertFalse(try v("2.5", "5.94.1") < v("2.5", "5.94.1"))
        for text in ["", "2..5", "2.beta", "2.-1", "٢.٥", "2.999999999999999999999999"] {
            XCTAssertNil(MirsaNotificationVersion(text, build: "1"))
            XCTAssertNil(MirsaNotificationVersion("2.5", build: text))
        }
    }
    func testFeedIdentityUnsortedAndMalformed() throws {
        let feed: [String: Any] = ["apps": [
            ["bundleIdentifier":"com.alaa.mirsa.setup", "versions":[["version":"2.4", "buildVersion":"5.88.1"]]],
            ["bundleIdentifier":"com.alaa.player", "versions":[["version":"999", "buildVersion":"999"]]],
            ["bundleIdentifier":"com.alaa.mirsa", "versions":[["version":"2.9","buildVersion":"5.94.1"],["version":"2.10","buildVersion":"5.95.1"]]]
        ]]
        let data = try JSONSerialization.data(withJSONObject: feed)
        XCTAssertEqual(try MirsaNotificationPayload.update(data, bundle:"com.alaa.mirsa").label, "2.10")
        XCTAssertEqual(try MirsaNotificationPayload.update(data, bundle:"com.alaa.mirsa.setup").label, "2.4")
        XCTAssertThrowsError(try MirsaNotificationPayload.update(data, bundle:"com.alaa.player"))
        XCTAssertThrowsError(try MirsaNotificationPayload.update(Data("{}".utf8), bundle:"com.alaa.mirsa"))
        let duplicate = try JSONSerialization.data(withJSONObject: ["apps":[
            ["bundleIdentifier":"com.alaa.mirsa","versions":[["version":"2.5","buildVersion":"x"]]],
            ["bundleIdentifier":"com.alaa.mirsa","versions":[]]
        ]])
        XCTAssertThrowsError(try MirsaNotificationPayload.update(duplicate,bundle:"com.alaa.mirsa"))
    }
    func testBroadcastLocaleAllOwnerIDAndMalformed() throws {
        func row(_ language: String, target: String = "all") -> [String: Any] {
            ["id":UUID().uuidString,"title":"Hello","message":"Text","language":language,"target":target,"createdAt":1000]
        }
        let rows = [row("ar"),row("all"),row("de"),row("ar",target:"owner")]
        let data = try JSONSerialization.data(withJSONObject:["version":1,"messages":rows])
        XCTAssertEqual(try MirsaNotificationPayload.broadcasts(data,locale:"ar",ownerAuthorized:false).count,2)
        XCTAssertEqual(try MirsaNotificationPayload.broadcasts(data,locale:"ar",ownerAuthorized:true).count,3)
        for lang in ["en","kmr","ckb"] {
            XCTAssertEqual(try MirsaNotificationPayload.broadcasts(data,locale:lang,ownerAuthorized:true).count,1)
        }
        for bad in [
            ["version":1,"messages":[rows[0],rows[0]]],
            ["version":2,"messages":[]],
            ["version":1,"messages":[["id":"bad"]]],
            ["version":1,"messages":[row("tr")]]
        ] as [[String: Any]] {
            XCTAssertThrowsError(try MirsaNotificationPayload.broadcasts(JSONSerialization.data(withJSONObject:bad),locale:"ar",ownerAuthorized:true))
        }
        XCTAssertThrowsError(try MirsaNotificationPayload.broadcasts(Data("unavailable".utf8),locale:"ar",ownerAuthorized:true))
    }
    func testDedupeSurvivesRestartAndDoesNotMarkFailureOrOffPermission() async throws {
        let suite = "mirsa.tests.notifications." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let ledger = MirsaNotificationLedger(defaults:defaults)
        let off = await ledger.deliver(id:"off",enabled:false,permitted:{ true },submit:{ XCTFail("disabled") })
        XCTAssertFalse(off)
        let denied = await ledger.deliver(id:"denied",enabled:true,permitted:{ false },submit:{ XCTFail("denied") })
        XCTAssertFalse(denied)
        let failed = await ledger.deliver(id:"retry",enabled:true,permitted:{ true },submit:{ throw URLError(.notConnectedToInternet) })
        XCTAssertFalse(failed)
        let retried = await ledger.deliver(id:"retry",enabled:true,permitted:{ true },submit:{})
        XCTAssertTrue(retried)
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        let second = MirsaNotificationLedger(defaults:secondDefaults)
        let duplicate = await second.deliver(id:"retry",enabled:true,permitted:{ true },submit:{ XCTFail("persisted") })
        XCTAssertFalse(duplicate)
        let afterDenied = await ledger.deliver(id:"denied",enabled:true,permitted:{ true },submit:{})
        XCTAssertTrue(afterDenied)
        let afterOff = await ledger.deliver(id:"off",enabled:true,permitted:{ true },submit:{})
        XCTAssertTrue(afterOff)
    }
    func testConcurrentRefreshOnlySchedulesOnce() async throws {
        let suite="mirsa.tests.concurrent."+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let ledger=MirsaNotificationLedger(defaults:defaults)
        actor Count {
            var value=0
            func submitted() { value+=1 }
        }
        let count=Count()
        await withTaskGroup(of:Bool.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    await ledger.deliver(id:"same-message",enabled:true,permitted:{ true },submit:{
                        try await Task.sleep(nanoseconds:10_000_000)
                        await count.submitted()
                    })
                }
            }
            var successes=0
            for await result in group { if result { successes+=1 } }
            XCTAssertEqual(successes,1)
        }
        let actual = await count.value
        XCTAssertEqual(actual,1)
    }
    func testCancellationRetries() async throws {
        let suite="mirsa.tests.cancel."+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let ledger=MirsaNotificationLedger(defaults:defaults)
        let work=Task {
            await ledger.deliver(id:"cancelled",enabled:true,permitted:{
                try? await Task.sleep(nanoseconds:50_000_000)
                return true
            },submit:{ XCTFail("cancelled work submitted") })
        }
        work.cancel()
        let cancelled=await work.value
        XCTAssertFalse(cancelled)
        let retry=await ledger.deliver(id:"cancelled",enabled:true,permitted:{true},submit:{})
        XCTAssertTrue(retry)
    }
    func testRefreshPlistRegistrationAndFiveLanguages() throws {
        // This bundle is the app test host, not a synthetic plist.
        let identifiers=Bundle.main.object(forInfoDictionaryKey:"BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        XCTAssertTrue(identifiers.contains("com.alaa.mirsa.announcements.refresh"))
        XCTAssertTrue((Bundle.main.object(forInfoDictionaryKey:"UIBackgroundModes") as? [String] ?? []).contains("fetch"))
        for language in AppLanguage.allCases {
            XCTAssertTrue(["ar","en","de","kmr","ckb"].contains(language.rawValue))
        }
    }
}
