import Foundation
import Network
import Combine

/// Update-only path gate. Never infer Wi-Fi from an interface merely being available.
@MainActor
final class UpdateNetworkPath: ObservableObject {
    static let shared = UpdateNetworkPath()
    enum State: Equatable { case unknown, wifi, cellular, unavailable }
    @Published private(set) var state: State = .unknown
    var permitsUpdate: Bool { state == .wifi }
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.alaa.mirsa.update-network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state = Self.classify(satisfied: path.status == .satisfied,
                                      usesWiFi: path.usesInterfaceType(.wifi),
                                      usesCellular: path.usesInterfaceType(.cellular))
            Task { @MainActor [weak self] in self?.state = state }
        }
        monitor.start(queue: queue)
    }

    nonisolated static func classify(satisfied: Bool, usesWiFi: Bool, usesCellular: Bool) -> State {
        guard satisfied else { return .unavailable }
        if usesCellular { return .cellular }
        return usesWiFi ? .wifi : .unknown
    }

    static var requirement: String {
        tr("Wi-Fi is required (mandatory) + enable LocalDevVPN and check your pairing file.",
           "لازم تكون على وايفاي (إجباري) + فعّل LocalDevVPN وتأكد من صحة ملف الاقتران",
           ckb: "دەبێت بە وایفای ببەسترێیت (ناچاری) + LocalDevVPN چالاک بکە و لە دروستی فایلی جووتکردنەوە دڵنیابە.",
           kmr: "Divê li ser Wi-Fi bî (mecbûrî) + LocalDevVPN çalak bike û rastiya pela cotkirinê kontrol bike.")
    }

    var blockedExplanation: String {
        if state == .cellular {
            return tr("Updating is disabled on cellular. Connect to Wi-Fi to enable Update now.",
                      "التحديث موقف عالبيانات الخلوية. اتصل بالوايفاي ليتفعّل زر حدّث هلّق.",
                      ckb: "نوێکردنەوە لەسەر داتای مۆبایل ناچالاکە. بە وایفای ببەستەوە تا دوگمەی نوێکردنەوە چالاک بێت.",
                      kmr: "Nûkirin li ser daneyên mobîlê neçalak e. Bi Wi-Fi ve girêbide da bişkojka nûkirinê çalak bibe.")
        }
        return tr("Waiting for a confirmed Wi-Fi connection. Update now stays disabled until Wi-Fi is active.",
                  "ناطر اتصال وايفاي مؤكّد. زر حدّث هلّق بيضل موقف لحتى يصير الوايفاي شغّال.",
                  ckb: "چاوەڕێی پەیوەندییەکی وایفای دڵنیاین. دوگمەی نوێکردنەوە تا چالاکبوونی وایفای ناچالاک دەمێنێتەوە.",
                  kmr: "Li benda girêdana Wi-Fi ya piştrast e. Bişkojka nûkirinê heta Wi-Fi çalak bibe neçalak dimîne.")
    }
}
