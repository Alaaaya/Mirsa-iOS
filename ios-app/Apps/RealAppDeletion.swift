import Foundation

/// Commit local deletion only after installation_proxy confirms completion.
/// Failure leaves both the persisted record and all local files untouched.
enum RealAppDeletion {
    enum Failure: Error { case notConfirmed }

    @MainActor
    static func perform(networkReady: Bool, bundleID: String?,
                        uninstall: (String) async throws -> Bool,
                        commit: () -> Void) async throws {
        guard networkReady, let bundleID, !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.notConfirmed
        }
        guard try await uninstall(bundleID) else { throw Failure.notConfirmed }
        commit()
    }

    static var failureMessage: String {
        tr("The app was not removed from Mirsa because its iPhone uninstall could not be confirmed. Turn on LocalDevVPN and check your pairing file, then try Delete again. You can also delete the app from the iPhone Home Screen. No free app slot has been confirmed.",
           "ما شلنا التطبيق من مرسى لأن ما تأكدنا إنه انحذف من الآيفون. شغّل LocalDevVPN وتأكد من ملف الاقتران وجرّب الحذف مرة تانية. فيك كمان تحذفه من الشاشة الرئيسية للآيفون. ما تأكدنا إنه صار في مكان لتطبيق إضافي.",
           ckb: "بەرنامەکە لە میرسا نەسڕایەوە چونکە سڕینەوەی لە ئایفۆن پشتڕاست نەکرایەوە. LocalDevVPN چالاک بکە و فایلی جووتکردنەوە بپشکنە، پاشان دووبارە هەوڵ بدە. دەتوانیت لە شاشەی سەرەکی ئایفۆنیش بیسڕیتەوە. بەتاڵبوونی شوێنی بەرنامە پشتڕاست نەکراوەتەوە.",
           kmr: "Sepan ji Mirsa nehat rakirin ji ber ku jêbirina wê ji iPhone nehat piştrastkirin. LocalDevVPN çalak bike û pela cotkirinê kontrol bike, paşê dîsa biceribîne. Tu dikarî sepanê ji ekrana sereke ya iPhone jî jê bibî. Cihê vala yê sepanê nehatiye piştrastkirin.")
    }
}
