import Foundation

enum WallpaperMakerStrings {
    enum Key: String, CaseIterable {
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
        .chooseTendies: ["Choose .tendies from Files…", "اختار .tendies من الملفات…", ".tendies aus Dateien wählen…", ".tendies ji Pelan hilbijêre…", ".tendies لە فایلەکان هەڵبژێرە…"],
        .importMore: ["Import more wallpapers…", "ضيف خلفيات تانية…", "Weitere Hintergründe importieren…", "Dîwarên din bîne hundir…", "هاوردەکردنی پاشبنەمای زیاتر…"],
        .importHint: ["Choose a .tendies file, or copy wallpapers into On My iPhone › Mirsa.", "اختار ملف .tendies، أو انسخ الخلفيات إلى على الـ iPhone الخاص بي › Mirsa.", "Wähle eine .tendies-Datei oder kopiere Hintergründe nach Auf meinem iPhone › Mirsa.", "Pelekî .tendies hilbijêre an dîwaran li ser Li ser iPhone-a min › Mirsa kopî bike.", "فایلێکی .tendies هەڵبژێرە، یان پاشبنەماکان کۆپی بکە بۆ لەسەر iPhoneی من › Mirsa."],

        .unlock: ["Unlock animation", "حركة فتح القفل", "Entsperr-Animation", "Anîmasyona vekirina kilîtê", "جووڵەی کردنەوەی قوفڵ"],
        .off: ["Off", "مطفي", "Aus", "Girtî", "ناچالاک"],
        .unlockZoom: ["Zoom", "تكبير", "Vergrößern", "Mezinkirin", "گەورەکردن"],
        .unlockSlide: ["Slide", "سحب", "Verschieben", "Şemitandin", "خلیسکان"],
        .gyro: ["Tilt with device motion (experimental)", "ميلان مع حركة الجهاز (تجريبي)", "Neigung mit Gerätebewegung (experimentell)", "Xwarbûn bi tevgera amûrê (ceribandin)", "لاربوون بە جووڵەی ئامێر (تاقیکردنەوە)"],
        .floating: ["Gentle floating animation", "حركة طفو خفيفة", "Sanftes Schweben", "Tevgera hêsan a herikînê", "جووڵەی هێواشی هەڵواسین"],
        .effectsHelp: ["Effects start off. Unlock uses system states, floating loops every 6 seconds, tilt uses motion mappings. Device support varies and has not been verified on your iOS. Preview shows layout only, not system effects.", "الحركات مطفية بالأصل. فتح القفل حسب حالة النظام، الطفو بيتكرر كل ٦ ثواني، والميلان حسب حركة الجهاز. الدعم حسب iOS ولسّا مو مجرّب على جهازك. المعاينة للترتيب بس، مو لحركات النظام.", "Effekte sind zunächst aus. Entsperren nutzt Systemzustände, Schweben einen 6-Sekunden-Zyklus und Neigung Bewegungszuordnungen. Unterstützung hängt von iOS ab und ist auf deinem Gerät nicht geprüft. Vorschau zeigt nur das Layout.", "Bandor di destpêkê de girtî ne. Vekirin rewşên pergalê bi kar tîne; herikîn her 6 çirkeyan dubare dibe; xwarbûn nexşeyên tevgerê bi kar tîne. Piştgirî bi iOS ve girêdayî ye û li amûra te nehatiye ceribandin. Pêşdîtin tenê rêzê nîşan dide.", "کاریگەرییەکان لە بنەڕەتدا ناچالاکن. کردنەوە دۆخی سیستەم بەکاردەهێنێت، هەڵواسین هەر ٦ چرکە دووبارە دەبێتەوە، لاربوون نەخشەی جووڵە بەکاردەهێنێت. پشتگیری بە iOS بەستراوە و لە ئامێرەکەت تاقی نەکراوەتەوە. پێشبینین تەنها ڕێکخستن پیشان دەدات."],
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
        .depthHelp: ["Off by default. Uses separate background/floating PosterBoard layers; clock overlap depends on iOS. No automatic cutout. Motion effects have separate switches. Supply transparent PNG cutouts for foregrounds. Preview shows stacking, not the system clock.", "مطفي بالأصل. بيعمل طبقات خلف وأمام منفصلة لـ PosterBoard؛ تغطية الساعة حسب iOS. ما في قصّ تلقائي للشخص. الحركات إلها مفاتيح منفصلة. استعمل PNG شفاف للأمام. المعاينة بتبيّن ترتيب الصور، مو ساعة النظام.", "Standardmäßig aus. Separate PosterBoard-Ebenen für Hintergrund und schwebenden Vordergrund; Uhrüberdeckung hängt von iOS ab. Kein automatisches Freistellen. Bewegungseffekte separat einschalten. Transparente PNGs für Vordergründe verwenden. Vorschau zeigt nur die Bildreihenfolge, nicht die Systemuhr.", "Ji destpêkê ve girtî ye. Tebeqeyên paşplan û pêşplana veqetandî yên PosterBoard bi kar tîne; serdemjimêrê bi iOS ve girêdayî ye. Bê qutkirina kesan a otomatîk. Bandorên tevgerê bişkojkên cuda hene. Ji bo pêşplanê PNG-ya şefaf bi kar bîne. Pêşdîtin tenê rêza wêneyan nîşan dide, ne demjimêra pergalê.", "لە بنەڕەتدا ناچالاکە. چینەکانی پاشەوە و پێشەوەی PosterBoard جیاوازن؛ داپۆشینی کاتژمێر بە iOS بەستراوە. بڕینی خۆکاری کەس نییە. کاریگەرییەکانی جووڵە دوگمەی جیاوازیان هەیە. بۆ پێشەوە PNGی شەفاف بەکاربهێنە. پێشبینین تەنها ڕیزی وێنەکان پیشان دەدات، نەک کاتژمێری سیستەم."],
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
