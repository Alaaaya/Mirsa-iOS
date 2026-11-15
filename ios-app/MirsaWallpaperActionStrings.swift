import Foundation

/// Localized text for the owner-approved wallpaper install, respring and owned-management flow.
enum MirsaWallpaperActionStrings {
    enum Key: CaseIterable {
        case installTitle, installBody, installConfirm, cancel
        case respringTitle, respringBody, respringConfirm, respringLater
        case ownedTitle, ownedFooter, ownedEmpty, refresh
        case deleteItem, deleteTitle, deleteBody, deleteConfirm
        case cleanup, cleanupTitle, cleanupBody, cleanupConfirm
        case deleteDone, cleanupDone, failedPrefix, busy, importRemoveHint
    }
    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let column: Int
        switch language {
        case .english: column = 0
        case .arabic: column = 1
        case .german: column = 2
        case .kurmanji: column = 3
        case .sorani: column = 4
        }
        return values[key]![column]
    }
    static let values: [Key: [String]] = [
        .installTitle: ["Install selected wallpapers?", "تثبّت الخلفيات المحددة؟", "Ausgewählte Hintergründe installieren?", "Wênesaziyên hilbijartî saz bikim?", "ئەو وێنەزەمینانە دابمەزرێنم کە هەڵبژێردراون؟"],
        .installBody: ["This copies the selected wallpapers into the iOS wallpaper gallery. Your imported files stay as they are. You will be asked separately before anything restarts.", "رح ينسخ الخلفيات المحددة لمعرض خلفيات iOS. ملفاتك المستوردة بتضل متل ما هي. رح نسألك لحالها قبل ما يعيد التشغيل أي شي.", "Die ausgewählten Hintergründe werden in die iOS-Hintergrundgalerie kopiert. Deine importierten Dateien bleiben unverändert. Vor einem Neustart wirst du separat gefragt.", "Ev wênesaziyên hilbijartî ji galeriya wênesaziyên iOS re kopî dike. Pelên te yên hatine import kirin wekî xwe dimînin. Berî ku tiştek ji nû ve dest pê bike, dê ji te ji aliyekî din ve bê pirsîn.", "ئەمە وێنەزەمینە هەڵبژێردراوەکان کۆپی دەکات بۆ گالەری وێنەزەمینەی iOS. فایلە هاوردەکراوەکانت وەک خۆیان دەمێننەوە. پێش هەر دووبارە دەستپێکردنەوەیەک جیا پرسیارت لێ دەکرێت."],
        .installConfirm: ["Install", "تثبيت", "Installieren", "Saz bike", "دامەزراندن"],
        .cancel: ["Cancel", "إلغاء", "Abbrechen", "Betal bike", "پاشگەزبوونەوە"],
        .respringTitle: ["Restart the screen now?", "تعيد تشغيل الشاشة هلق؟", "Bildschirm jetzt neu starten?", "Ekranê niha ji nû ve dest pê bikim?", "ئێستا شاشەکە دووبارە دەست پێ بکەمەوە؟"],
        .respringBody: ["iOS needs a screen restart to show the change in the wallpaper gallery. The screen may flicker, apps or the screen may restart, and unsaved work can be lost. Success is only confirmed when you check the wallpaper gallery yourself.", "لازم iOS يعيد تشغيل الشاشة ليظهر التغيير بمعرض الخلفيات. الشاشة ممكن ترمش، والتطبيقات أو الشاشة ممكن ترجع تشتغل من جديد، وأي شي مو محفوظ ممكن يضيع. ما منعتبره نجح إلا لما تتأكد بنفسك من معرض الخلفيات.", "iOS braucht einen Neustart des Bildschirms, damit die Änderung in der Galerie erscheint. Der Bildschirm kann flackern, Apps oder der Bildschirm können neu starten, nicht gespeicherte Arbeit kann verloren gehen. Erfolg gilt erst, wenn du die Galerie selbst geprüft hast.", "iOS ji bo nîşandana guhertinê di galeriyê de pêdivî bi vemirandin û vekirina ekranê heye. Dibe ku ekran biriqe, sepan an ekran ji nû ve dest pê bikin û xebata tomarnekirî winda bibe. Serkeftin tenê piştî ku tu bi xwe galeriyê kontrol bikî tê pejirandin.", "iOS پێویستی بە دووبارە دەستپێکردنەوەی شاشە هەیە بۆ پیشاندانی گۆڕانکاری لە گالەری. ڕەنگە شاشە بتروسکێتەوە، ئەپەکان یان شاشە دووبارە دەست پێ بکەنەوە و ئەو کارەی پاشەکەوت نەکراوە لەدەست بچێت. سەرکەوتن تەنها دوای ئەوە دەسەلمێندرێت کە خۆت گالەری بپشکنیت."],
        .respringConfirm: ["Restart screen", "إعادة تشغيل الشاشة", "Bildschirm neu starten", "Ekranê ji nû ve dest pê bike", "دووبارە دەستپێکردنەوەی شاشە"],
        .respringLater: ["Not now", "مو هلق", "Nicht jetzt", "Ne niha", "نەک ئێستا"],
        .ownedTitle: ["Custom wallpapers found", "خلفيات مخصصة موجودة", "Gefundene eigene Hintergründe", "Wênesaziyên taybet ên hatine dîtin", "وێنەزەمینە تایبەتەکانی دۆزراوە"],
        .ownedFooter: ["Only custom wallpapers that were positively recognized are listed, including ones from Mirsa, Placard or other apps. Unknown and Apple items are hidden. Deleting one removes it from the system gallery but keeps your imported .tendies file.", "بس الخلفيات المخصصة يلي تعرفنا عليها بشكل مؤكد، منها يلي من مرسى أو Placard أو تطبيقات تانية. العناصر المجهولة وعناصر Apple مخفية. الحذف بيشيلها من معرض النظام وبيخلي ملف .tendies المستورد.", "Es werden nur eindeutig erkannte eigene Hintergründe angezeigt, auch von Mirsa, Placard oder anderen Apps. Unbekannte und Apple-Elemente sind ausgeblendet. Löschen entfernt sie aus der System-Galerie, deine importierte .tendies-Datei bleibt erhalten.", "Tenê wênesaziyên taybet ên bi piştrastî hatine nasîn tên nîşandan, yên ji Mirsa, Placard an sepanên din jî. Hêmanên nenas û yên Apple veşartî ne. Jêbirin wan ji galeriya pergalê radike lê pela te ya .tendies a import kirî dihêle.", "تەنها ئەو وێنەزەمینە تایبەتانە پیشان دەدرێن کە بە دڵنیایی ناسراونەتەوە، لەوانە ئەوانەی مرسی، Placard یان ئەپی تر. بەشە نەناسراو و ئەوانەی Apple شاراوەن. سڕینەوە لە گالەری سیستەم لایدەبات بەڵام فایلی .tendies هاوردەکراوەکەت دەهێڵێتەوە."],
        .ownedEmpty: ["No custom wallpapers recognized.", "ما في خلفيات مخصصة معروفة.", "Keine eigenen Hintergründe erkannt.", "Tu wênesaziyek taybet nehat nasîn.", "هیچ وێنەزەمینەیەکی تایبەت نەناسرایەوە."],
        .refresh: ["Refresh list", "تحديث القائمة", "Liste aktualisieren", "Lîsteyê nû bike", "نوێکردنەوەی لیست"],
        .deleteItem: ["Delete from gallery", "حذف من المعرض", "Aus Galerie löschen", "Ji galeriyê jê bibe", "سڕینەوە لە گالەری"],
        .deleteTitle: ["Delete this wallpaper?", "تحذف هالخلفية؟", "Diesen Hintergrund löschen?", "Ev wênesazî jê bibim?", "ئەم وێنەزەمینەیە بسڕمەوە؟"],
        .deleteBody: ["This removes only the selected custom wallpaper from the system gallery. It may have been installed by another app. Your imported .tendies file stays, and other items are not touched. If it is your active lock screen, what happens is unknown. You will be asked separately about restarting the screen.", "هيك بيحذف بس الخلفية المخصصة يلي اخترتها من معرض النظام. ممكن تكون مثبّتة من تطبيق تاني. ملف .tendies المستورد بيضل وباقي العناصر ما بتنلمس. إذا كانت شاشة القفل الحالية، ما منعرف شو رح يصير. رح نسألك لحالها عن إعادة تشغيل الشاشة.", "Dadurch wird nur der ausgewählte eigene Hintergrund aus der System-Galerie entfernt. Er kann von einer anderen App installiert worden sein. Deine importierte .tendies-Datei bleibt erhalten, andere Elemente bleiben unberührt. Ist er dein aktiver Sperrbildschirm, ist das Ergebnis unbekannt. Zum Neustart des Bildschirms wirst du separat gefragt.", "Ev tenê wênesaziya taybet a hilbijartî ji galeriya pergalê radike. Dibe ku ji hêla sepanek din ve hatibe saz kirin. Pela te ya .tendies dimîne û hêmanên din nayên destlêdan. Heke ev kilîta te ya çalak be, encam nayê zanîn. Dê derbarê vemirandina ekranê de ji te ji aliyekî din bê pirsîn.", "ئەمە تەنها ئەو وێنەزەمینە تایبەتەی هەڵتبژاردووە لە گالەری سیستەم دەسڕێتەوە. لەوانەیە ئەپێکی تر دایمەزراندبێت. فایلی .tendies هاوردەکراوەکەت دەمێنێتەوە و بەشەکانی تر دەست لێ نادرێن. ئەگەر شاشەی قفڵی چالاکت بێت، ئەنجامەکەی نەزانراوە. جیا پرسیارت لێ دەکرێت دەربارەی دووبارە دەستپێکردنەوەی شاشە."],
        .deleteConfirm: ["Delete", "حذف", "Löschen", "Jê bibe", "سڕینەوە"],
        .cleanup: ["Clean up Mirsa leftovers", "تنظيف مخلفات مرسى", "Mirsa-Reste aufräumen", "Bermahiyên Mirsa paqij bike", "پاککردنەوەی پاشماوەکانی مرسی"],
        .cleanupTitle: ["Clean up leftovers?", "تنظّف المخلفات؟", "Reste aufräumen?", "Bermahiyan paqij bikim?", "پاشماوەکان پاک بکەمەوە؟"],
        .cleanupBody: ["This removes only Mirsa's own temporary extraction files and records of wallpapers that are verified to be gone already. No wallpaper is deleted from the system gallery and no restart is needed.", "هيك بيشيل بس الملفات المؤقتة يلي مرسى فكّها بنفسه وسجلات خلفيات تأكدنا إنها انحذفت أصلاً. ما بيحذف أي خلفية من معرض النظام وما بدك إعادة تشغيل.", "Entfernt nur Mirsas eigene temporäre Entpackdateien und Einträge zu Hintergründen, die nachweislich schon weg sind. Es wird keine Hintergrundgalerie-Datei gelöscht und kein Neustart ist nötig.", "Ev tenê pelên demkî yên Mirsa bi xwe û tomarên wênesaziyên ku piştrast bûye jixwe nemane radike. Tu wênesazî ji galeriya pergalê nayê jêbirin û ji nû ve destpêkirin ne pêwîst e.", "ئەمە تەنها فایلە کاتییەکانی مرسی خۆی و تۆمارەکانی ئەو وێنەزەمینانە دەسڕێتەوە کە دڵنیابووین پێشتر نەماون. هیچ وێنەزەمینەیەک لە گالەری سیستەم ناسڕدرێتەوە و پێویست بە دووبارە دەستپێکردنەوە ناکات."],
        .cleanupConfirm: ["Clean up", "نظّف", "Aufräumen", "Paqij bike", "پاک بکەرەوە"],
        .deleteDone: ["Deleted from the gallery. Check the wallpaper gallery yourself.", "انحذفت من المعرض. تأكد بنفسك من معرض الخلفيات.", "Aus der Galerie gelöscht. Prüfe die Hintergrundgalerie selbst.", "Ji galeriyê hate jêbirin. Galeriyê bi xwe kontrol bike.", "لە گالەری سڕایەوە. خۆت گالەری بپشکنە."],
        .cleanupDone: ["Cleanup finished.", "خلص التنظيف.", "Aufräumen abgeschlossen.", "Paqijkirin qediya.", "پاککردنەوە تەواو بوو."],
        .failedPrefix: ["Failed: ", "فشل: ", "Fehlgeschlagen: ", "Têk çû: ", "شکستی هێنا: "],
        .busy: ["Please wait, another wallpaper job is running.", "استنى، في شغلة خلفيات تانية شغالة.", "Bitte warten, ein anderer Hintergrund-Vorgang läuft.", "Ji kerema xwe bisekine, karekî din yê wênesaziyê dixebite.", "تکایە چاوەڕێ بە، کارێکی تری وێنەزەمینە کار دەکات."],
        .importRemoveHint: ["The trash icon in the list above only removes the imported file.", "أيقونة الحذف بالقائمة فوق بتشيل الملف المستورد بس.", "Das Papierkorb-Symbol oben entfernt nur die importierte Datei.", "Îkona çopê di lîsteya jorîn de tenê pela import kirî radike.", "ئایکۆنی تەنەکەی خۆڵ لە لیستی سەرەوە تەنها فایلە هاوردەکراوەکە لادەبات."]
    ]
}
