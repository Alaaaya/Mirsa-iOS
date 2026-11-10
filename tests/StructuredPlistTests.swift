import XCTest
import SwiftUI
import UIKit
@testable import Mirsa
final class StructuredPlistTests: XCTestCase {
    func testAllTypesBothFormatsAndMutations() throws {
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let values: [String: Any] = [
                "text": "عربي < &", "integer": NSNumber(value: Int64.max),
                "real": 1.25, "flag": true, "data": Data([0, 1, 255]),
                "date": Date(timeIntervalSince1970: 1000),
                "array": ["one", ["nested": "value"]] as [Any], "dict": ["key": "value"]
            ]
            var doc = try PlistDocument(data: PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0))
            try doc.add(at: [.key("dict")], key: "new", type: "string", text: "kept")
            try doc.rename(at: [.key("dict"), .key("new")], to: "renamed")
            XCTAssertThrowsError(try doc.rename(at: [.key("dict"), .key("renamed")], to: "key"))
            try doc.remove(at: [.key("array"), .index(0)])
            let reread = try PlistDocument(data: doc.serialized())
            XCTAssertEqual(reread.format, format)
            XCTAssertEqual((reread.value(at: [.key("integer")]) as? NSNumber)?.int64Value, Int64.max)
            XCTAssertEqual(reread.value(at: [.key("data")]) as? Data, Data([0, 1, 255]))
            XCTAssertEqual(reread.value(at: [.key("date")]) as? Date, values["date"] as? Date)
            XCTAssertEqual(reread.value(at: [.key("dict"), .key("renamed")]) as? String, "kept")
            XCTAssertEqual(reread.value(at: [.key("array"), .index(0), .key("nested")]) as? String, "value")
            let raw = try PlistDocument(xmlText: reread.xmlText(), preserving: format)
            XCTAssertEqual(try raw.serialized().prefix(6), try reread.serialized().prefix(6))
        }
    }
    func testInvalidRawDuplicateEntityAndFiniteNumbers() throws {
        XCTAssertThrowsError(try PlistDocument(xmlText: "<plist><dict><key>a</key><string>one</string><key>a</key><string>two</string></dict></plist>", preserving: .binary))
        XCTAssertThrowsError(try PlistDocument(xmlText: "<!DOCTYPE plist [<!ENTITY x SYSTEM 'https://example.com'>]><plist><string>&x;</string></plist>", preserving: .xml))
        XCTAssertThrowsError(try PlistDocument.parse("nan", as: "real"))
        XCTAssertThrowsError(try PlistDocument.parse("1.5", as: "integer"))
    }
    func testInvalidSaveKeepsOriginalBytesAndOverlay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["key": "original"], format: .binary, options: 0)
        let file = bundle.appendingPathComponent("settings.plist")
        try bytes.write(to: file)
        let manager = try BundleFileManager(root: bundle, stagingDirectory: root.appendingPathComponent("staged"))
        XCTAssertThrowsError(try manager.stageWrite("settings.plist", data: Data("invalid XML".utf8)))
        XCTAssertTrue(manager.overlay.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}

@MainActor
final class StructuredPlistScreenshotTests: XCTestCase {
    func testRealEditorScreenAt430x932() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.myapp", "CFBundleDisplayName": "My App",
            "CFBundleVersion": "1.0.0", "LSRequiresIPhoneOS": true,
            "UIBackgroundModes": ["audio"], "UISupportedInterfaceOrientations": ["Portrait", "LandscapeLeft", "LandscapeRight"],
            "UIAppFonts": ["Font.ttf", "Bold.ttf"], "NSCameraUsageDescription": "We need access to your camera.",
            "NSPhotoLibraryUsageDescription": "Access your photos to share moments.",
            "NSLocationWhenInUseUsageDescription": "Allow access to your location.",
            "UIRequiredDeviceCapabilities": ["arm64": true], "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        let manager = try BundleFileManager(root: bundle, stagingDirectory: root.appendingPathComponent("stage"))
        let entry = try manager.list("").first { $0.name == "Info.plist" }.unwrap()
        let controller = UIHostingController(rootView: NavigationStack { StructuredPlistEditor(manager: manager, entry: entry) })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = controller; window.makeKeyAndVisible()
        let ready = expectation(description: "render real editor task")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ready.fulfill() }
        wait(for: [ready], timeout: 5)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 430, height: 932)).image { _ in
            controller.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: 430, height: 932), afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Structured-plist-real-430x932"; attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
private extension Optional {
    func unwrap() throws -> Wrapped { try XCTUnwrap(self) }
}
