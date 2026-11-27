// Simulator-only async refresh proof. No app-state invalidation is performed by this host.
// Runtime contract, ONLY under MIRSA_RUNTIME_TESTING:
// int MirsaRuntimeTestConfigure(void): isolated empty table, real hooks installed,
// enabled runtime, no network or production activation/cache writes.
// int MirsaRuntimeTestApplyJSON(const char *): calls real ApplyOnlineEntries(array),
// including the production refresh coordinator. Returns 1 on success, otherwise 0.
// Configure is before any UI construction; Apply is the only stimulus after capture.
import UIKit
import SwiftUI
import Darwin

private let source = "异步刷新验证"
private let expectedArabic = "التحقق من التحديث"
private var bodyEvaluations = 0
private struct RetainedText: View {
    var body: some View {
        let _ = { bodyEvaluations += 1 }()
        Text(verbatim: source)
            .font(.system(size: 34))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
    }
}

// Separate UIKit fixture mode exercises the actual runtime notice, not a replica.
private final class BannerModalFixtureController: UIViewController {
    private let notice: @convention(c) (Int32) -> Int32
    private let status = UILabel()

    init(notice: @escaping @convention(c) (Int32) -> Int32) {
        self.notice = notice
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Fixture is programmatic") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.semanticContentAttribute = .forceRightToLeft
        let show = UIButton(type: .system)
        show.setTitle("إظهار تنبيه التعريب", for: .normal)
        show.accessibilityIdentifier = "notice.show"
        show.addTarget(self, action: #selector(showNotice), for: .touchUpInside)
        let other = UIButton(type: .system)
        other.setTitle("فتح نافذة أخرى", for: .normal)
        other.accessibilityIdentifier = "notice.other-modal"
        other.addTarget(self, action: #selector(showOtherModal), for: .touchUpInside)
        status.accessibilityIdentifier = "notice.consumed"
        status.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [show, other, status])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
        updateStatus()
    }
    private func updateStatus() {
        precondition(Thread.isMainThread)
        status.text = notice(2) == 1 ? "مستهلك" : "غير مستهلك"
    }
    private func requestNotice() {
        precondition(Thread.isMainThread)
        _ = notice(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.updateStatus() }
    }
    @objc private func showNotice() { requestNotice() }
    @objc private func showOtherModal() {
        let other = UIAlertController(title: nil, message: "نافذة تجريبية أخرى", preferredStyle: .alert)
        other.addAction(UIAlertAction(title: "إغلاق", style: .default))
        present(other, animated: true) { self.requestNotice() }
    }
}

@main
final class RefreshProof: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var host: UIHostingController<RetainedText>!
    private var label: UILabel!
    private var apply: (@convention(c) (UnsafePointer<CChar>) -> Int32)!
    private var initialPixels = Data()
    private var initialPNG = Data()
    private var bodiesBefore = 0
    private var receipt: [String: Any] = [:]
    private var library: UnsafeMutableRawPointer?
    private let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let sampleRect = CGRect(x: 10, y: 100, width: 360, height: 150)

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fatalError("Cannot create fixture output") }
        guard let libraryPath = Bundle.main.path(forResource: "MirsaTranslate", ofType: "dylib"),
              let handle = dlopen(libraryPath, RTLD_NOW | RTLD_GLOBAL) else {
            finish(false, "dylib_load_failed")
            return true
        }
        library = handle
        guard let configureSymbol = dlsym(handle, "MirsaRuntimeTestConfigure"),
              let applySymbol = dlsym(handle, "MirsaRuntimeTestApplyJSON") else {
            finish(false, "missing_test_exports")
            return true
        }
        let configure = unsafeBitCast(configureSymbol, to: (@convention(c) () -> Int32).self)
        apply = unsafeBitCast(applySymbol, to: (@convention(c) (UnsafePointer<CChar>) -> Int32).self)
        guard configure() == 1 else {
            finish(false, "test_configure_failed")
            return true
        }
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-LaunchProof"),
           idx + 1 < ProcessInfo.processInfo.arguments.count {
            runLaunchProof(ProcessInfo.processInfo.arguments[idx + 1], handle: handle)
            return true
        }
        if ProcessInfo.processInfo.arguments.contains("-BannerModalFixture") {
            guard let noticeSymbol = dlsym(handle, "MirsaRuntimeTestPendingNotice") else {
                finish(false, "missing_notice_test_export")
                return true
            }
            let notice = unsafeBitCast(noticeSymbol, to: (@convention(c) (Int32) -> Int32).self)
            if ProcessInfo.processInfo.arguments.contains("-ResetNotice") { _ = notice(1) }
            let win = UIWindow(frame: UIScreen.main.bounds)
            win.overrideUserInterfaceStyle = .light
            win.rootViewController = BannerModalFixtureController(notice: notice)
            window = win
            win.makeKeyAndVisible()
            return true
        }
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.overrideUserInterfaceStyle = .light
        win.rootViewController = controller
        window = win
        host = UIHostingController(rootView: RetainedText())
        controller.addChild(host)
        host.view.frame = sampleRect
        controller.view.addSubview(host.view)
        host.didMove(toParent: controller)
        label = UILabel(frame: CGRect(x: 10, y: 300, width: 360, height: 120))
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 34)
        label.textColor = .black
        label.backgroundColor = .white
        label.text = source
        controller.view.addSubview(label)
        win.makeKeyAndVisible()
        // Give SwiftUI time to shape/cache the first Chinese line before dictionary arrival.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.beforeMerge() }
        return true
    }

    // Honest launch-time acceptance. Modes (each is a separate real process launch):
    // control: no embedded dictionary, no cache -> must stay Chinese.
    // embedded: full scoped dictionary in MirsaTranslations.json shape, loaded before any UI -> first frame Arabic.
    // ota-seed: OTA entries arrive and persist to disk cache (no UI claim).
    // ota-verify: fresh process loads persisted cache before UI -> first frame Arabic.
    private func runLaunchProof(_ mode: String, handle: UnsafeMutableRawPointer) {
        receipt["mode"] = mode
        receipt["source"] = source
        receipt["expected"] = expectedArabic
        let name = "launch-\(mode).json"
        func write(_ passed: Bool, _ reason: String) {
            receipt["passed"] = passed; receipt["reason"] = reason
            receipt["liveSwiftUIRefreshClaimed"] = false
            if let d = try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: output.appendingPathComponent(name), options: .atomic)
            }
        }
        if mode == "ota-seed" {
            let entries: [[String: Any]] = [["source": source, "translation": expectedArabic, "provenance": "kat", "version": 1]]
            guard let data = try? JSONSerialization.data(withJSONObject: ["entries": entries]),
                  let json = String(data: data, encoding: .utf8) else { write(false, "json"); return }
            let applied = json.withCString { apply($0) }
            // Cache write happens synchronously inside the production apply path.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { write(applied == 1, applied == 1 ? "seeded_to_disk_cache" : "apply_failed") }
            return
        }
        if mode == "embedded" {
            guard let s = dlsym(handle, "MirsaRuntimeTestLoadConfigJSON") else { write(false, "missing_export"); return }
            let load = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>) -> Int32).self)
            let cfg: [String: Any] = ["translations": [source: expectedArabic], "substrings": [:], "regex": [], "revision": "x"]
            guard let d = try? JSONSerialization.data(withJSONObject: cfg), let j = String(data: d, encoding: .utf8),
                  j.withCString({ load($0) }) == 1 else { write(false, "load_config_failed"); return }
        } else if mode == "ota-verify" || mode == "control" {
            guard let s = dlsym(handle, "MirsaRuntimeTestLoadCache") else { write(false, "missing_export"); return }
            let load = unsafeBitCast(s, to: (@convention(c) () -> Int32).self)
            guard load() == 1 else { write(false, "load_cache_failed"); return }
        } else { write(false, "unknown_mode"); return }
        // UI is built only now: first frame already has the dictionary.
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.overrideUserInterfaceStyle = .light
        win.rootViewController = controller
        window = win
        let hostVC = UIHostingController(rootView: RetainedText())
        controller.addChild(hostVC)
        hostVC.view.frame = sampleRect
        controller.view.addSubview(hostVC.view)
        hostVC.didMove(toParent: controller)
        win.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let shown = self.image(hostVC.view)
            self.save(shown, "launch-\(mode).png")
            let ref = UIHostingController(rootView: Text(verbatim: expectedArabic).font(.system(size: 34)).foregroundColor(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white))
            controller.addChild(ref); ref.view.frame = self.sampleRect
            controller.view.addSubview(ref.view); ref.didMove(toParent: controller)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let mismatch = self.difference(self.pixels(shown), self.pixels(self.image(ref.view)))
                self.receipt["arabicReferenceMismatchFraction"] = mismatch
                self.receipt["bodyEvaluations"] = bodyEvaluations
                if mode == "control" { write(mismatch > 0.01, mismatch > 0.01 ? "control_stays_chinese" : "control_unexpectedly_arabic") }
                else { write(mismatch < 0.002, mismatch < 0.002 ? "first_frame_arabic" : "first_frame_not_arabic") }
            }
        }
    }
    private func image(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
    private func pixels(_ image: UIImage) -> Data {
        guard let cg = image.cgImage else { return Data() }
        var buffer = Data(count: cg.width * cg.height * 4)
        let succeeded = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return succeeded ? buffer : Data()
    }
    // Changed pixels, not compressed PNG byte differences.
    private func difference(_ left: Data, _ right: Data) -> Double {
        guard !left.isEmpty, left.count == right.count else { return 1 }
        let a = [UInt8](left), b = [UInt8](right)
        var changed = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            if abs(Int(a[i]) - Int(b[i])) > 12 ||
               abs(Int(a[i+1]) - Int(b[i+1])) > 12 ||
               abs(Int(a[i+2]) - Int(b[i+2])) > 12 { changed += 1 }
        }
        return Double(changed) / Double(a.count / 4)
    }
    private func save(_ image: UIImage, _ name: String) {
        try? image.pngData()?.write(to: output.appendingPathComponent(name), options: .atomic)
    }
    private func beforeMerge() {
        let before = image(host.view)
        save(before, "swiftui-before.png")
        initialPixels = pixels(before)
        initialPNG = before.pngData() ?? Data()
        bodiesBefore = bodyEvaluations
        receipt["source"] = source
        receipt["expected"] = expectedArabic
        receipt["labelBefore"] = label.text ?? ""
        receipt["bodyEvaluationsBefore"] = bodiesBefore
        receipt["retainedHostIdentity"] = String(describing: ObjectIdentifier(host))
        guard label.text == source, !initialPixels.isEmpty else {
            finish(false, "initial_state_not_untranslated")
            return
        }
        let entries: [[String: Any]] = [
            ["source": source, "translation": expectedArabic, "provenance": "kat", "version": 1]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: ["entries": entries]),
              let json = String(data: data, encoding: .utf8) else {
            finish(false, "fixture_json_failed")
            return
        }
        // Delayed arrival on a queue like the runtime network callback. This must
        // schedule the production main-thread reapply itself, not rely on the host.
        DispatchQueue.global(qos: .userInitiated).async {
            let applied = json.withCString { self.apply($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard applied == 1 else { self.finish(false, "apply_failed"); return }
                self.afterMerge()
            }
        }
    }
    private func afterMerge() {
        let after = image(host.view)
        save(after, "swiftui-after-retained.png")
        let retainedPixels = pixels(after)
        receipt["labelAfter"] = label.text ?? ""
        receipt["bodyEvaluationsAfter"] = bodyEvaluations
        receipt["retainedHostIdentityAfter"] = String(describing: ObjectIdentifier(host))
        receipt["changedPixelFraction"] = difference(initialPixels, retainedPixels)
        save(image(label), "uikit-after.png")
        if let window { save(image(window), "screen-after-retained.png") }

        // Only AFTER recording retained content, construct literal Arabic and
        // original Chinese references. Neither participates in the retained tree.
        let reference = UIHostingController(rootView:
            Text(verbatim: expectedArabic).font(.system(size: 34)).foregroundColor(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white))
        guard let parent = window?.rootViewController else { finish(false, "no_window"); return }
        parent.addChild(reference)
        reference.view.frame = sampleRect
        parent.view.addSubview(reference.view)
        reference.didMove(toParent: parent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let expected = self.image(reference.view)
            self.save(expected, "swiftui-reference-arabic.png")
            let match = self.difference(retainedPixels, self.pixels(expected))
            self.receipt["arabicReferenceMismatchFraction"] = match
            let changed = self.difference(self.initialPixels, retainedPixels)
            let labelOK = self.label.text == expectedArabic
            self.receipt["uikitPassed"] = labelOK
            // Require positive changed pixels AND match against a literal Arabic
            // reference, not merely a layout/blink/invalidation difference.
            let swiftUIOK = changed > 0.002 && match < 0.002
            self.receipt["swiftuiPassed"] = swiftUIOK
            self.finish(labelOK && swiftUIOK,
                swiftUIOK ? (labelOK ? "verified" : "uikit_reapply_failed") :
                    "retained_swiftui_not_proven_arabic")
        }
    }
    private func finish(_ passed: Bool, _ reason: String) {
        receipt["passed"] = passed
        receipt["reason"] = reason
        receipt["fixtureMutatedSwiftUIState"] = false
        receipt["fixtureReassignedExistingLabel"] = false
        receipt["osVersion"] = UIDevice.current.systemVersion
        receipt["evidence"] = ["swiftui-before.png", "swiftui-after-retained.png",
            "swiftui-reference-arabic.png", "uikit-after.png", "screen-after-retained.png"]
        if let json = try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: output.appendingPathComponent("refresh-result.json"), options: .atomic)
        }
        // Keep the app alive for simulator screenshots and evidence extraction.
    }
}
