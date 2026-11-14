import Foundation

enum WallpaperMakerStrings {
    enum Key: String, CaseIterable {
        case selectAll, deselectAll, collectionsType, suggestedPhotosType, mercuryType, containerType
        case cutout, cutoutHelp, cutoutReady, cutoutNoSubject, cutoutUnavailable, cutoutPreparing, connectionHint, containerUnavailable, copyVerified, applyFailed
        case chooseTendies, importMore, importHint
        case unlock, off, unlockZoom, unlockSlide, gyro, floating, effectsHelp
        case middle, zoom, horizontal, vertical, describe, plan, manualFallback
        case title, steps, photos, video, files, crop, layers, background, foreground, reorder, depth, depthHelp
        case preview, generate, preparing, share, importFile, ready, error, remove, clear, videoHelp, compatibility, limit
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
        .selectAll: ["Select All", "اختار الكل", "Alle auswählen", "Hemûyan hilbijêre", "هەمووی هەڵبژێرە"],
        .deselectAll: ["Deselect All", "شيل تحديد الكل", "Auswahl aufheben", "Hilbijartina hemûyan rake", "هەڵبژاردنی هەمووی لاببە"],
        .collectionsType: ["Collections", "المجموعات", "Sammlungen", "Koleksiyon", "کۆمەڵەکان"],
        .suggestedPhotosType: ["Suggested Photos", "صور مقترحة", "Vorgeschlagene Fotos", "Wêneyên pêşniyarkirî", "وێنە پێشنیارکراوەکان"],
        .mercuryType: ["Mercury", "ميركوري", "Mercury", "Mercury", "میرکیوری"],
        .containerType: ["App Container", "حاوية التطبيق", "App-Container", "Konteynera sepanê", "کۆنتەینەری ئەپ"],
        .applyFailed: ["Wallpaper installation could not be completed. Check Flash Log before retrying; it includes copy and rollback details.", "ما اكتمل تطبيق الخلفية. شوف سجل التطبيق قبل ما تعيد المحاولة؛ فيه تفاصيل النسخ والتراجع عن التغييرات.", "Hintergrund konnte nicht vollständig installiert werden. Vor erneutem Versuch Flash-Protokoll mit Kopier- und Wiederherstellungsdetails prüfen.", "Sazkirina dîwarê temam nebû. Berî dubarekirinê Flash Log bixwîne; hûrguliyên kopîkirin û vegerandinê tê de ne.", "دامەزراندنی پاشبنەما تەواو نەبوو. پێش دووبارەکردنەوە تۆمارەکە ببینە؛ وردەکاری کۆپی و گەڕاندنەوەی گۆڕانکارییەکانی تێدایە."],
        .copyVerified: ["Wallpaper files copied and read back successfully. Restarting the interface next. Appearance in the system gallery still needs to be checked on this iPhone.", "ملفات الخلفية اننسخت وتأكدت منها بعد النسخ. هلأ رح تعيد الواجهة تشغيلها. بعدها لازم تتأكد من ظهور الخلفية بمعرض النظام عهالآيفون.", "Dateien kopiert und durch Rücklesen geprüft. Die Oberfläche startet anschließend neu. Erscheinen in der Systemgalerie muss auf diesem iPhone noch geprüft werden.", "Pel hatin kopîkirin û bi xwendina paşê piştrastkirin. Rûkar dê ji nû ve dest pê bike. Divê xuya bûna di galeriya pergalê de li ser vê iPhone-ê were kontrolkirin.", "فایلەکان کۆپی کران و بە خوێندنەوە پشتڕاست کرانەوە. ڕووکار دووبارە دەست پێدەکاتەوە. دەرکەوتن لە گەلەری سیستەم لەم iPhoneە هێشتا پێویستی بە پشکنین هەیە."],
        .containerUnavailable: ["PosterBoard access could not be verified. Nothing was applied. See Flash Log for details.", "ما قدرت أتأكد من الوصول لخلفيات النظام. ما طبّقت شي. التفاصيل بسجل التطبيق.", "PosterBoard-Zugriff nicht bestätigt. Nichts angewendet. Details im Flash-Protokoll.", "Gihîştina PosterBoard nehat piştrastkirin. Tiştek nehat sepandin. Hûrgulî di Flash Log de ne.", "دەستگەیشتن بە PosterBoard پشتڕاست نەکرایەوە. هیچ جێبەجێ نەکرا. وردەکاری لە تۆمارەکەدایە."],
        .connectionHint: ["Connect to Wi-Fi, turn on LocalDevVPN, keep the iPhone unlocked and try again. Technical details remain in Flash Log.", "اتصل بالواي فاي وشغّل LocalDevVPN، خلّي الآيفون مفتوح وجرّب كمان مرة. التفاصيل التقنية موجودة بسجل التطبيق.", "Mit WLAN verbinden, LocalDevVPN einschalten, iPhone entsperrt lassen und erneut versuchen. Technische Details stehen im Flash-Protokoll.", "Bi Wi-Fi ve girêbide, LocalDevVPN veke, iPhone vekirî bihêle û dîsa biceribîne. Hûrguliyên teknîkî di Flash Log de ne.", "بە Wi-Fi پەیوەست ببە، LocalDevVPN چالاک بکە، iPhone کراوە بهێڵە و دووبارە تاقی بکەوە. وردەکارییە تەکنیکییەکان لە تۆمارەکەدان."],
        .cutoutPreparing: ["Preparing cutout on this device…", "عم نقصّ الصورة عالجهاز…", "Motiv wird lokal freigestellt…", "Li ser amûrê tê qutkirin…", "لەسەر ئامێرەکەت دەبڕدرێت…"],
        .cutoutUnavailable: ["Cutout is unavailable here. Using the original photo; a transparent PNG also works.", "القصّ مو متاح هون. استعملت الصورة الأصلية؛ فيك تختار PNG شفاف كمان.", "Freistellen hier nicht verfügbar. Original wird verwendet; transparentes PNG ist ebenfalls möglich.", "Qutkirin li vir ne berdest e. Wêneya orîjînal tê bikaranîn; PNG-ya şefaf jî dibe.", "بڕین لێرە بەردەست نییە. وێنەی ڕەسەن بەکاردێت؛ PNGی شەفافیش دەکرێت."],
        .cutoutNoSubject: ["No clear subject found. Using the original photo. Try a photo with a distinct person or object.", "ما لقيت شخص أو غرض واضح للقصّ. استعملت الصورة الأصلية. جرّب صورة فيها شخص أو غرض أوضح.", "Kein klares Motiv gefunden. Original wird verwendet. Foto mit deutlichem Motiv versuchen.", "Kes an tiştekî zelal nehat dîtin. Wêneya orîjînal tê bikaranîn. Wêneyeke bi mijareke zelal biceribîne.", "کەس یان شتێکی ڕوون نەدۆزرایەوە. وێنەی ڕەسەن بەکاردێت. وێنەیەک بە بابەتێکی ڕوون تاقی بکەوە."],
        .cutoutReady: ["Foreground cutout ready", "قصّ صورة الأمام جاهز", "Freigestelltes Motiv bereit", "Qutkirina pêşplanê amade ye", "بڕینی پێشەوە ئامادەیە"],
        .cutoutHelp: ["On by default for foreground layers. Processed only on this device, never uploaded. Turn off to restore the original photo. Preview and saved file use the same image.", "شغّال بالأصل لصور الأمام. القصّ عالجهاز بس، وما منرفع صورك. طفيه لترجع الصورة الأصلية. المعاينة والملف بيستعملوا نفس الصورة.", "Für Vordergrundebenen standardmäßig an. Nur lokal, kein Upload. Ausschalten stellt das Original wieder her. Vorschau und Datei verwenden dasselbe Bild.", "Ji bo pêşplanê ji destpêkê vekirî ye. Tenê li ser amûrê, bê barkirin. Bigire da wêneya orîjînal vegere. Pêşdîtin û pel heman wêneyê bi kar tînin.", "بۆ چینەکانی پێشەوە لە بنەڕەتدا چالاکە. تەنها لەسەر ئامێرەکەت، بەبێ بارکردن. ناچالاکی بکە بۆ گەڕاندنەوەی وێنەی ڕەسەن. پێشبینین و فایل هەمان وێنە بەکاردەهێنن."],
        .cutout: ["Remove foreground background", "قصّ تلقائي", "Vordergrund freistellen", "Paşplana wêneya pêşê rake", "لابردنی پاشبنەمای وێنەی پێشەوە"],
        .chooseTendies: ["Choose .tendies from Files…", "اختار .tendies من الملفات…", ".tendies aus Dateien wählen…", ".tendies ji Pelan hilbijêre…", ".tendies لە فایلەکان هەڵبژێرە…"],
        .importMore: ["Import more wallpapers…", "ضيف خلفيات تانية…", "Weitere Hintergründe importieren…", "Dîwarên din bîne hundir…", "هاوردەکردنی پاشبنەمای زیاتر…"],
        .importHint: ["Choose a .tendies file, or copy wallpapers into On My iPhone › Mirsa.", "اختار ملف .tendies، أو انسخ الخلفيات إلى على الـ iPhone الخاص بي › Mirsa.", "Wähle eine .tendies-Datei oder kopiere Hintergründe nach Auf meinem iPhone › Mirsa.", "Pelekî .tendies hilbijêre an dîwaran li ser Li ser iPhone-a min › Mirsa kopî bike.", "فایلێکی .tendies هەڵبژێرە، یان پاشبنەماکان کۆپی بکە بۆ لەسەر iPhoneی من › Mirsa."],

        .unlock: ["Unlock animation", "حركة فتح القفل", "Entsperr-Animation", "Anîmasyona vekirina kilîtê", "جووڵەی کردنەوەی قوفڵ"],
        .off: ["Off", "مطفي", "Aus", "Girtî", "ناچالاک"],
        .unlockZoom: ["Zoom", "تكبير", "Vergrößern", "Mezinkirin", "گەورەکردن"],
        .unlockSlide: ["Slide", "سحب", "Verschieben", "Şemitandin", "خلیسکان"],
        .gyro: ["Tilt with device motion (experimental)", "ميلان مع حركة الجهاز (تجريبي)", "Neigung mit Gerätebewegung (experimentell)", "Xwarbûn bi tevgera amûrê (ceribandin)", "لاربوون بە جووڵەی ئامێر (تاقیکردنەوە)"],
        .floating: ["Gentle floating animation", "حركة طفو خفيفة", "Sanftes Schweben", "Tevgera hêsan a herikînê", "جووڵەی هێواشی هەڵواسین"],
        .effectsHelp: ["Several photos start with depth, unlock zoom and tilt enabled. Your changes are preserved. Floating is optional. Preview shows layout only, not system effects; system animation support depends on iOS.", "مع كذا صورة بيشتغل العمق وتكبير فتح القفل والميلان بالأصل. اختياراتك ما بتتغيّر. الطفو اختياري. المعاينة للترتيب بس، ودعم الحركات حسب iOS.", "Mehrere Fotos starten mit Tiefe, Entsperr-Zoom und Neigung. Eigene Einstellungen bleiben erhalten. Schweben ist optional. Vorschau zeigt nur Layout; Systemanimationen hängen von iOS ab.", "Bi gelek wêneyan kûrahî, zooma vekirinê û xwarbûn vekirî ne. Guhertinên te diparêzin. Herikîn bijarte ye. Pêşdîtin tenê rêzê nîşan dide; anîmasyon bi iOS ve girêdayî ye.", "بە چەند وێنەیەک قوڵایی و گەورەکردنی کردنەوە و لاربوون چالاکن. گۆڕانکارییەکانت دەپارێزرێن. هەڵواسین هەڵبژاردەییە. پێشبینین تەنها ڕێکخستنە؛ جووڵەی سیستەم بە iOS بەستراوە."],
        .middle: ["Middle", "بالنص", "Mitte", "Navîn", "ناوەڕاست"],
        .zoom: ["Zoom", "تكبير", "Zoom", "Mezinkirin", "گەورەکردن"],
        .horizontal: ["Horizontal position", "المكان يمين ويسار", "Horizontale Position", "Cihê asoyî", "شوێنی ئاسۆیی"],
        .vertical: ["Vertical position", "المكان فوق وتحت", "Vertikale Position", "Cihê stûnî", "شوێنی ستوونی"],
        .describe: ["Describe your layout", "اكتب كيف بدك ياها", "Beschreibe dein Layout", "Bêje tu çawa dixwazî", "بنووسە چۆنی دەوێت"],
        .plan: ["Suggest layout (text only)", "اقترح ترتيب (نص بس)", "Layout vorschlagen (nur Text)", "Rêzê pêşniyar bike (tenê nivîs)", "پێشنیاری ڕێکخستن (تەنها دەق)"],
        .manualFallback: ["Layout suggestion unavailable. Your photos are unchanged; adjust them manually.", "الاقتراح مو متاح هلأ. صورك متل ما هي، فيك ترتّبها بإيدك.", "Layout-Vorschlag nicht verfügbar. Fotos unverändert; bitte manuell anpassen.", "Pêşniyara rêzê ne berdest e. Wêneyên te neguherîn; bi destan sererast bike.", "پێشنیاری ڕێکخستن بەردەست نییە. وێنەکانت نەگۆڕاون؛ بە دەست ڕێکیان بخە."],
        .title: ["Make a .tendies wallpaper", "اعمل خلفية .tendies", ".tendies-Hintergrund erstellen", "Dîwarê .tendies çêke", "دروستکردنی پاشبنەمای .tendies"],
        .steps: ["Pick photos or a video, preview, then generate. Save with Share or import into the gallery. Nothing is applied until you select a wallpaper and tap Apply below.", "اختار صور أو فيديو، شوف المعاينة وبعدين اعمل الملف. احفظه من المشاركة أو ضيفه للمعرض. ما بيتطبّق شي لحتى تختار الخلفية وتكبس تطبيق تحت.", "Fotos oder Video wählen, Vorschau prüfen und Datei erstellen. Über Teilen speichern oder in die Galerie importieren. Erst mit der Anwenden-Taste unten wird ein ausgewählter Hintergrund angewendet.", "Wêne an vîdyoyekê hilbijêre, pêşdîtinê bibîne û pelê çêke. Bi Parvekirinê tomar bike an têxe galeriyê. Heta ku tu dîwar hilnebijêrî û li jêr Sepandinê nebitikînî, tiştek nayê sepandin.", "وێنە یان ڤیدیۆ هەڵبژێرە، پێشبینین ببینە و فایل دروست بکە. بە هاوبەشکردن پاشەکەوتی بکە یان بیخە گەلەری. تا پاشبنەما هەڵنەبژێریت و دوگمەی جێبەجێکردنی خوارەوە نەدەیت، هیچ ناگۆڕێت."],
        .photos: ["Photos as layers", "صور كطبقات", "Fotos als Ebenen", "Wêne wek tebeqe", "وێنە وەک چین"],
        .video: ["Video from Photos", "فيديو من الاستوديو", "Video aus Fotos", "Vîdyo ji Wêneyan", "ڤیدیۆ لە وێنەکان"],
        .files: ["Photos or video from Files", "صور أو فيديو من الملفات", "Fotos oder Video aus Dateien", "Wêne an vîdyo ji Pelan", "وێنە یان ڤیدیۆ لە فایلەکان"],
        .crop: ["Center-crop photos to screen", "قصّ الصور من النص لتعبّي الشاشة", "Fotos mittig auf Bildschirm zuschneiden", "Wêneyan ji navendê li gor ekranê bibire", "بڕینی ناوەڕاستی وێنە بەپێی شاشە"],
        .layers: ["Photo layers", "طبقات الصور", "Fotoebenen", "Tebeqeyên wêneyan", "چینەکانی وێنە"],
        .background: ["Background", "بالخلف", "Hintergrund", "Paşplan", "پاشەوە"],
        .foreground: ["Foreground", "بالأمام", "Vordergrund", "Pêşplan", "پێشەوە"],
        .reorder: ["Drag handles to reorder, back to front. Choose Background or Foreground for each photo. With clock depth on, foreground layers render above all background layers.", "اسحب من المسكة لترتّب من ورا لقدّام. اختار لكل صورة بالخلف أو بالأمام. لما تشغّل عمق الساعة، طبقات الأمام بتكون فوق كل طبقات الخلف.", "An den Griffen ziehen, von hinten nach vorne. Pro Foto Hintergrund oder Vordergrund wählen. Bei Uhr-Tiefe liegen alle Vordergrundebenen über den Hintergrundebenen.", "Destikan bikişîne da ku ji paş ber bi pêş rêz bikî. Ji bo her wêneyê Paşplan an Pêşplan hilbijêre. Bi kûrahiya demjimêrê, tebeqeyên pêşplanê li ser hemû paşplanan in.", "بە دەستگرتەکان ڕیزیان بگۆڕە، لە پاشەوە بۆ پێشەوە. بۆ هەر وێنە پاشەوە یان پێشەوە هەڵبژێرە. بە قوڵایی کاتژمێر، هەموو چینەکانی پێشەوە لەسەر پاشەوەن."],
        .depth: ["Foreground over clock (experimental)", "الأمام فوق الساعة (تجريبي)", "Vordergrund über Uhr (experimentell)", "Pêşplan li ser demjimêrê (ceribandin)", "پێشەوە لەسەر کاتژمێر (تاقیکردنەوە)"],
        .depthHelp: ["Multiple photos start with depth enabled. Foreground cutout is local and reversible. Clock overlap depends on iOS; preview shows image stacking, not the system clock.", "مع كذا صورة العمق بيشتغل بالأصل. قصّ صورة الأمام عالجهاز وفيك ترجّع الأصل. تغطية الساعة حسب iOS؛ المعاينة لترتيب الصور، مو ساعة النظام.", "Bei mehreren Fotos ist Tiefe zunächst aktiv. Vordergrund wird lokal und umkehrbar freigestellt. Uhrüberdeckung hängt von iOS ab; Vorschau zeigt Bildreihenfolge, nicht die Systemuhr.", "Bi gelek wêneyan kûrahî di destpêkê de vekirî ye. Qutkirina pêşplanê herêmî û vegerbar e. Serdemjimêrê bi iOS ve girêdayî ye; pêşdîtin rêza wêneyan nîşan dide, ne demjimêra pergalê.", "بە چەند وێنەیەک قوڵایی لە بنەڕەتدا چالاکە. بڕینی پێشەوە ناوخۆییە و دەگەڕێتەوە. داپۆشینی کاتژمێر بە iOS بەستراوە؛ پێشبینین ڕیزی وێنەکانە نەک کاتژمێری سیستەم."],
        .preview: ["Preview", "معاينة", "Vorschau", "Pêşdîtin", "پێشبینین"],
        .generate: ["Generate .tendies", "اعمل ملف .tendies", ".tendies erstellen", ".tendies çêke", "دروستکردنی .tendies"],
        .preparing: ["Preparing wallpaper…", "عم نجهّز الخلفية…", "Hintergrund wird erstellt…", "Dîwar tê amadekirin…", "پاشبنەما ئامادە دەکرێت…"],
        .share: ["Share / Save to Files", "شارك / احفظ بالملفات", "Teilen / In Dateien sichern", "Parve bike / Di Pelan de tomar bike", "هاوبەشکردن / پاشەکەوت لە فایلەکان"],
        .importFile: ["Import into wallpaper gallery", "ضيفه لمعرض الخلفيات", "In Hintergrundgalerie importieren", "Têxe galeriya dîwaran", "هاوردەکردن بۆ گەلەری پاشبنەما"],
        .ready: ["File ready. Save it or import it when you choose.", "الملف جاهز. احفظه أو ضيفه للمعرض وقت ما بدك.", "Datei bereit. Jetzt speichern oder bei Bedarf importieren.", "Pel amade ye. Dema ku tu dixwazî tomar bike an têxe galeriyê.", "فایل ئامادەیە. هەرکات ویستت پاشەکەوت یان هاوردەی بکە."],
        .error: ["Could not prepare this media. Try another photo or video.", "ما قدرت جهّز هالملف. جرّب صورة أو فيديو تاني.", "Dieses Medium konnte nicht verarbeitet werden. Anderes Foto oder Video versuchen.", "Ev medya nehat amadekirin. Wêne an vîdyoyeke din biceribîne.", "ئەم میدیایە ئامادە نەکرا. وێنە یان ڤیدیۆیەکی تر تاقی بکەوە."],
        .remove: ["Remove layer", "شيل الطبقة", "Ebene entfernen", "Tebeqeyê rake", "سڕینەوەی چین"],
        .clear: ["Clear selection", "فضّي الاختيار", "Auswahl leeren", "Hilbijartinê paqij bike", "بەتاڵکردنی هەڵبژاردە"],
        .videoHelp: ["Video: first 10 seconds, center-cropped to screen. Photos: up to 8 separate layers; crop off fits the entire image.", "الفيديو أول ١٠ ثواني وبينقصّ من النص ليعبّي الشاشة. الصور لحد ٨ طبقات منفصلة؛ طفي القصّ لتظهر الصورة كاملة.", "Video: erste 10 Sekunden, mittiger Bildschirmzuschnitt. Fotos: bis zu 8 separate Ebenen; ohne Zuschnitt wird das ganze Bild eingepasst.", "Vîdyo: 10 çirkeyên pêşîn, ji navendê li gor ekranê. Wêne: heta 8 tebeqeyên cuda; birînê bigire da ku tevahiya wêneyê xuya bibe.", "ڤیدیۆ یەکەم ١٠ چرکەیە و ناوەڕاست بەپێی شاشە دەبڕدرێت. وێنە تا ٨ چینی جیاواز؛ بڕین ناچالاک بکە بۆ بینینی تەواوی وێنە."],
        .compatibility: ["iOS (18.0 – 27.2 beta 2)", "iOS (18.0 – 27.2 beta 2)", "iOS (18.0 – 27.2 beta 2)", "iOS (18.0 – 27.2 beta 2)", "iOS (18.0 – 27.2 beta 2)"],
        .limit: ["Choose up to 8 photos, or one video on its own.", "اختار لحد ٨ صور، أو فيديو واحد لحاله.", "Bis zu 8 Fotos oder ein einzelnes Video wählen.", "Heta 8 wêne an tenê vîdyoyekê hilbijêre.", "تا ٨ وێنە یان تەنها یەک ڤیدیۆ هەڵبژێرە."]
    ]
}

/// Only translate recognized tunnel timeouts; unrelated errors retain their diagnostics.
enum TendiesConnectionHint {
    static func matches(_ raw: String) -> Bool {
        let text = raw.lowercased()
        return (text.contains("timed out") || text.contains("timeout")) &&
            (text.contains("mirsa_connection") || text.contains("rsd") || text.contains("lockdown") || text.contains("tunnel") || text.contains("remotexpc") || text.contains("remote xpc"))
    }
}
