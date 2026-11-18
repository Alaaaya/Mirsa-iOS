import Foundation

enum WallpaperMakerStrings {
    enum Key: String, CaseIterable {
        case gyroStrength, subtle, mediumStrength, strong, gyroHelp, unlockHelp, spin, spinHelp, particles, snow, leaves, stars, particlesHelp, sleepDim, sleepHelp, gradient, replicate, replicateHelp, blend, normalBlend, screenBlend, overlayBlend, blur, liquidGlass, glassHelp, scene, sceneShared, sceneLock, sceneHome, sceneHelp, homeHorizontal, homeVertical, sceneOutput
        case particleDirection, falling, rising
        case appearance, appearanceBoth, appearanceLight, appearanceDark, appearanceHelp
        case selectAll, deselectAll, collectionsType, suggestedPhotosType, mercuryType, containerType
        case cutout, cutoutHelp, cutoutReady, cutoutNoSubject, cutoutUnavailable, cutoutPreparing, connectionHint, containerUnavailable, copyVerified, applyFailed, respringHelp, motionPreset, motionLeft, motionRight, motionUp, motionDown, motionFloat
        case chooseTendies, importMore, importHint
        case editing, editHelp, editCancel, saveEdit, editLegacy, editSaved, editButton, notEditable
        case unlock, off, unlockZoom, unlockSlide, gyro, floating, effectsHelp, animatedPhotos, staticPhotos
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
        .editing: ["Editing:", "تعديل:", "Bearbeiten:", "Tê guhertin:", "دەستکاری:"],
        .editHelp: ["Your wallpaper's photos and effects are loaded below. Change anything, press Generate, then Save changes to replace this wallpaper.", "صور الخلفية وتأثيراتها محمّلة تحت. غيّر أي شي، اضغط إنشاء، وبعدين احفظ التعديلات لتستبدل هالخلفية.", "Fotos und Effekte deines Hintergrunds sind unten geladen. Ändere etwas, tippe auf Erstellen und speichere die Änderungen, um ihn zu ersetzen.", "Wêne û bandorên dîwarê te li jêr hatine barkirin. Tiştekî biguherîne, Çêke bike û paşê Guhertinan tomar bike da ku ev dîwar were guhertin.", "وێنە و کاریگەرییەکانی پاشبنەماکەت لە خوارەوە بار کراون. هەرچییەک بگۆڕە، دروستکردن دابگرە، پاشان گۆڕانکارییەکان پاشەکەوت بکە بۆ جێگرتنەوەی."],
        .editCancel: ["Cancel editing", "إلغاء التعديل", "Bearbeiten abbrechen", "Guhertinê betal bike", "هەڵوەشاندنەوەی دەستکاری"],
        .saveEdit: ["Save changes (replaces this wallpaper)", "احفظ التعديلات (تستبدل هالخلفية)", "Änderungen speichern (ersetzt diesen Hintergrund)", "Guhertinan tomar bike (vî dîwarî diguherîne)", "گۆڕانکارییەکان پاشەکەوت بکە (ئەم پاشبنەمایە دەگۆڕێت)"],
        .editLegacy: ["This wallpaper was made before saved settings existed. Its photos are loaded, but the old effects could not be read, so please choose the effects again.", "هالخلفية انعملت قبل ما نحفظ الإعدادات. الصور انحمّلت بس التأثيرات القديمة ما انقرت، فاختار التأثيرات من جديد.", "Dieser Hintergrund entstand, bevor Einstellungen gespeichert wurden. Die Fotos sind geladen, die alten Effekte ließen sich aber nicht lesen. Bitte wähle die Effekte neu.", "Ev dîwar berî tomarkirina mîhengan hatiye çêkirin. Wêne hatin barkirin lê bandorên kevn nehatin xwendin, ji kerema xwe bandoran dîsa hilbijêre.", "ئەم پاشبنەمایە پێش پاشەکەوتکردنی ڕێکخستنەکان دروست کراوە. وێنەکان بار کران بەڵام کاریگەرییە کۆنەکان نەخوێندرانەوە، تکایە کاریگەرییەکان دووبارە هەڵبژێرە."],
        .editSaved: ["Wallpaper updated.", "انحدّثت الخلفية.", "Hintergrund aktualisiert.", "Dîwar hate nûkirin.", "پاشبنەما نوێ کرایەوە."],
        .editButton: ["Edit wallpaper", "تعديل الخلفية", "Hintergrund bearbeiten", "Dîwarê biguherîne", "دەستکاریکردنی پاشبنەما"],
        .notEditable: ["This wallpaper can't be edited because its layers can't be read faithfully. It was not changed.", "ما بقدر أعدّل هالخلفية لأن طبقاتها ما بتنقرا بدقة. ما تغيّرت.", "Dieser Hintergrund kann nicht bearbeitet werden, weil seine Ebenen nicht originalgetreu gelesen werden können. Er wurde nicht verändert.", "Ev dîwar nayê guhertin ji ber ku qatên wê bi rastî nayên xwendin. Nehate guhertin.", "ئەم پاشبنەمایە ناتوانرێت دەستکاری بکرێت چونکە چینەکانی بە دروستی ناخوێندرێنەوە. نەگۆڕدرا."],
        .gyroStrength: ["Tilt strength", "قوة الميلان", "Neigungsstärke", "Hêza xwarbûnê", "هێزی لاربوون"],
        .subtle: ["Subtle", "خفيف", "Dezent", "Hindik", "کەم"],
        .mediumStrength: ["Medium", "وسط", "Mittel", "Navîn", "مامناوەند"],
        .strong: ["Strong", "قوي", "Stark", "Xurt", "بەهێز"],
        .gyroHelp: ["Tilt moves layers with the phone. Choose tilt or clock depth, not both.", "الصور بتميل مع الموبايل. اختار الميلان أو عمق الساعة، مو التنين سوا.", "Ebenen folgen der Neigung. Neigung oder Uhrtiefe wählen, nicht beides.", "Çîn bi telefonê re dilivin. Xwarbûn an kûrahiya demjimêrê hilbijêre, ne her du.", "چینەکان لەگەڵ مۆبایل دەجووڵێن. لاربوون یان قوڵایی کاتژمێر هەڵبژێرە، نەک هەردووکیان."],
        .unlockHelp: ["Zoom or slide between lock and home scenes. Choose each photo’s scene below.", "تكبير أو سحب بين القفل والرئيسية. اختار شاشة كل صورة من تحت.", "Zoom oder Gleiten zwischen Sperr- und Home-Bild. Szene je Foto unten wählen.", "Di navbera kilît û malê de mezinkirin an şemitandin. Dîmena her wêneyê li jêr hilbijêre.", "گەورەکردن یان خلیسکان لەنێوان قوفڵ و سەرەکی. دیمەنی هەر وێنەیەک لە خوارەوە هەڵبژێرە."],
        .spin: ["Slow rotation", "دوران بطيء", "Langsame Drehung", "Zivirîna hêdî", "سووڕانەوەی هێواش"],
        .spinHelp: ["One full turn repeats every 16 seconds.", "لفة كاملة بتتكرر كل ١٦ ثانية.", "Eine volle Drehung alle 16 Sekunden.", "Her 16 çirkeyan carekê tam dizivire.", "هەر ١٦ چرکە سووڕانەوەیەکی تەواو دووبارە دەبێتەوە."],
        .particles: ["Particles", "أشكال متحركة", "Partikel", "Parçe", "تەنۆلکە"],
        .snow: ["Snow", "ثلج", "Schnee", "Berf", "بەفر"],
        .leaves: ["Leaves", "ورق شجر", "Blätter", "Pel", "گەڵا"],
        .stars: ["Stars", "نجوم", "Sterne", "Stêrk", "ئەستێرە"],
        .particlesHelp: ["Small original shapes fall over the photos. Saved as emitter particles.", "أشكال صغيرة بتنزل فوق الصور وبتنحفظ كجزيئات متحركة بالملف.", "Kleine Formen fallen über die Fotos und werden als Partikel gespeichert.", "Şêweyên biçûk li ser wêneyan dadikevin û di pelê de tên tomarkirin.", "شێوە بچووکەکان بەسەر وێنەکاندا دادەبەزن و وەک تەنۆلکە پاشەکەوت دەکرێن."],
        .sleepDim: ["Dim in Sleep state", "تعتيم بوضع السكون", "Im Ruhezustand abdunkeln", "Di xewê de tarî bike", "تاریککردن لە دۆخی خەودا"],
        .sleepHelp: ["Dims photos in the wallpaper Sleep state. Does not enable Always On or bypass iOS limits.", "بيعتّم الصور بحالة سكون الخلفية. ما بيشغّل Always On ولا بيتجاوز قيود iOS.", "Dunkelt den Sleep-Zustand ab. Aktiviert kein Always On und umgeht keine iOS-Grenzen.", "Di rewşa xewê de tarî dike. Always On çalak nake û sînorên iOS derbas nake.", "لە دۆخی خەو وێنەکان تاریک دەکات. Always On چالاک ناکات و سنووری iOS تێناپەڕێنێت."],
        .gradient: ["Colour gradient behind photos", "تدرّج ألوان خلف الصور", "Farbverlauf hinter Fotos", "Rengên gavbi gav li paş wêneyan", "پلەڕەنگ لە پشت وێنەکان"],
        .replicate: ["Six rotated copies", "ست نسخ بشكل دائري", "Sechs gedrehte Kopien", "Şeş kopiyên zivirî", "شەش کۆپیی سووڕاو"],
        .replicateHelp: ["Repeats each photo around the centre. Transparent stickers work best.", "بيكرر كل صورة حوالين النص. أحلى مع الملصقات الشفافة.", "Wiederholt jedes Foto um die Mitte. Ideal für transparente Sticker.", "Her wêneyê li dora navendê dubare dike. Stîkerên şefaf baştir in.", "هەر وێنەیەک دەوروبەری ناوەڕاست دووبارە دەکات. ستیکەری شەفاف باشترە."],
        .blend: ["Layer blending", "مزج الطبقات", "Ebenenmischung", "Tevlihevkirina çînan", "تێکەڵکردنی چینەکان"],
        .normalBlend: ["Normal", "عادي", "Normal", "Asayî", "ئاسایی"],
        .screenBlend: ["Screen · lighter", "Screen · أفتح", "Screen · heller", "Screen · ronîtir", "Screen · ڕووناکتر"],
        .overlayBlend: ["Overlay · contrast", "Overlay · تباين", "Overlay · Kontrast", "Overlay · berevajî", "Overlay · کۆنتراست"],
        .blur: ["Soft blur", "ضبابية خفيفة", "Weichzeichnen", "Nezelaliya nerm", "تەمومژی نەرم"],
        .liquidGlass: ["Glass lens", "عدسة زجاج", "Glaslinse", "Lensa camê", "لینزی شووشە"],
        .glassHelp: ["A round refracting lens over the image, not blur. System rendering varies by iOS version.", "عدسة دائرية بتكسر الصورة، مو ضبابية. ظهورها حسب نسخة iOS.", "Runde brechende Linse, kein Weichzeichner. Darstellung hängt von iOS ab.", "Lenseke girover a şikandina wêneyê, ne nezelalî. Xuyabûn bi guhertoya iOS ve girêdayî ye.", "لینزێکی بازنەیی بۆ شکاندنی وێنە، نەک تەمومژ. دەرکەوتن بە وەشانی iOS بەستراوە."],
        .scene: ["Show photo on", "الصورة تظهر على", "Foto anzeigen auf", "Wêne li vir nîşan bide", "وێنە پیشان بدە لە"],
        .sceneShared: ["Both · shared layer", "التنين · طبقة مشتركة", "Beiden · gemeinsame Ebene", "Her du · çîna hevpar", "هەردووکیان · چینی هاوبەش"],
        .sceneLock: ["Lock Screen", "شاشة القفل", "Sperrbildschirm", "Ekrana kilîtê", "شاشەی قوفڵ"],
        .sceneHome: ["Home Screen", "الشاشة الرئيسية", "Home-Bildschirm", "Ekrana malê", "شاشەی سەرەکی"],
        .sceneHelp: ["Shared layers stay in both scenes. Lock/home-only photos switch on unlock.", "الطبقة المشتركة بتضل بالشاشتين. صور القفل والرئيسية بتتبدل وقت الفتح.", "Gemeinsame Ebenen bleiben in beiden Szenen. Andere wechseln beim Entsperren.", "Çînên hevpar di her du dîmenan de dimînin. Yên din di vekirinê de diguherin.", "چینە هاوبەشەکان لە هەردوو دیمەندا دەمێننەوە. ئەوانی تر لە کردنەوەدا دەگۆڕدرێن."],
        .homeHorizontal: ["Home position · horizontal offset", "مكانها بالرئيسية · أفقي", "Home-Position · horizontal", "Cihê malê · dûrahiya berwar", "شوێنی سەرەکی · ئاسۆیی"],
        .homeVertical: ["Home position · vertical offset", "مكانها بالرئيسية · عمودي", "Home-Position · vertikal", "Cihê malê · dûrahiya stûnî", "شوێنی سەرەکی · ستوونی"],
        .sceneOutput: ["Preview shows layout only. Scene and tilt effects play through iOS.", "المعاينة للترتيب بس. حركة الشاشات والميلان بيشغّلها iOS.", "Vorschau zeigt nur das Layout. Szenenwechsel und Neigung spielt iOS ab.", "Pêşdîtin tenê rêzê nîşan dide. Dîmen û xwarbûnê iOS dilîze.", "پێشبینین تەنها ڕێکخستنە. گۆڕینی دیمەن و لاربوون لەڕێی iOS کار دەکەن."],
        .particleDirection: ["Particle direction", "اتجاه الأشكال", "Partikelrichtung", "Arasteya parçeyan", "ئاراستەی تەنۆلکە"],
        .falling: ["Falling", "نازلة", "Fallend", "Dadikevin", "دادەبەزن"],
        .rising: ["Rising", "طالعة", "Aufsteigend", "Bilind dibin", "بەرزدەبنەوە"],
        .appearance: ["System appearance", "مظهر النظام", "Systemdarstellung", "Xuyabûna pergalê", "ڕووکارى سیستەم"],
        .appearanceBoth: ["Light and dark", "فاتح وداكن", "Hell und dunkel", "Ronî û tarî", "ڕووناک و تاریک"],
        .appearanceLight: ["Light only", "الفاتح بس", "Nur hell", "Tenê ronî", "تەنها ڕووناک"],
        .appearanceDark: ["Dark only", "الداكن بس", "Nur dunkel", "Tenê tarî", "تەنها تاریک"],
        .appearanceHelp: ["Changes with iOS light/dark appearance, not the time of day. Cannot combine with tilt yet.", "بتتبدل حسب مظهر iOS الفاتح والداكن، مو حسب الساعة. حالياً ما بتجتمع مع الميلان.", "Wechselt mit dem iOS-Hell-/Dunkelmodus, nicht nach Uhrzeit. Noch nicht mit Neigung kombinierbar.", "Bi moda ronî/tarî ya iOS diguhere, ne bi saetê. Hê bi xwarbûnê re nayê tevlihevkirin.", "بەپێی دۆخی ڕووناک/تاریکی iOS دەگۆڕێت، نەک کاتی ڕۆژ. هێشتا لەگەڵ لاربوون تێکەڵ ناکرێت."],
        .selectAll: ["Select All", "اختار الكل", "Alle auswählen", "Hemûyan hilbijêre", "هەمووی هەڵبژێرە"],
        .deselectAll: ["Deselect All", "شيل تحديد الكل", "Auswahl aufheben", "Hilbijartina hemûyan rake", "هەڵبژاردنی هەمووی لاببە"],
        .collectionsType: ["Collections", "المجموعات", "Sammlungen", "Koleksiyon", "کۆمەڵەکان"],
        .suggestedPhotosType: ["Suggested Photos", "صور مقترحة", "Vorgeschlagene Fotos", "Wêneyên pêşniyarkirî", "وێنە پێشنیارکراوەکان"],
        .mercuryType: ["Mercury", "ميركوري", "Mercury", "Mercury", "میرکیوری"],
        .containerType: ["App Container", "حاوية التطبيق", "App-Container", "Konteynera sepanê", "کۆنتەینەری ئەپ"],
        .applyFailed: ["Wallpaper installation could not be completed. Check Flash Log before retrying; it includes copy and rollback details.", "ما اكتمل تطبيق الخلفية. شوف سجل التطبيق قبل ما تعيد المحاولة؛ فيه تفاصيل النسخ والتراجع عن التغييرات.", "Hintergrund konnte nicht vollständig installiert werden. Vor erneutem Versuch Flash-Protokoll mit Kopier- und Wiederherstellungsdetails prüfen.", "Sazkirina dîwarê temam nebû. Berî dubarekirinê Flash Log bixwîne; hûrguliyên kopîkirin û vegerandinê tê de ne.", "دامەزراندنی پاشبنەما تەواو نەبوو. پێش دووبارەکردنەوە تۆمارەکە ببینە؛ وردەکاری کۆپی و گەڕاندنەوەی گۆڕانکارییەکانی تێدایە."],
        .copyVerified: ["Wallpaper files copied and read back. Confirm the separate screen-restart prompt, then check the iOS wallpaper gallery.", "ملفات الخلفية اننسخت وتأكدنا منها. وافق على سؤال إعادة تشغيل الشاشة، وبعدها تأكد من معرض خلفيات iOS.", "Dateien kopiert und durch Rücklesen geprüft. Bestätige die separate Bildschirm-Neustartfrage und prüfe danach die iOS-Hintergrundgalerie.", "Pel hatin kopîkirin û bi xwendina paşê piştrastkirin. Pirsê ji nû ve destpêkirina ekranê pejirîne, paşê galeriya iOS kontrol bike.", "فایلەکان کۆپی کران و بە خوێندنەوە پشتڕاست کرانەوە. داواکاری دووبارە دەستپێکردنەوەی شاشە پەسەند بکە، پاشان گالەری iOS بپشکنە."],
        .motionPreset: ["Continuous motion", "الحركة المستمرة", "Dauerbewegung", "Livîna domdar", "جووڵەی بەردەوام"],
        .motionLeft: ["Left first", "لليسار بالأول", "Zuerst links", "Pêşî çep", "سەرەتا بۆ چەپ"],
        .motionRight: ["Right first", "لليمين بالأول", "Zuerst rechts", "Pêşî rast", "سەرەتا بۆ ڕاست"],
        .motionUp: ["Up first", "لفوق بالأول", "Zuerst hoch", "Pêşî jor", "سەرەتا بۆ سەرەوە"],
        .motionDown: ["Down first", "لتحت بالأول", "Zuerst runter", "Pêşî jêr", "سەرەتا بۆ خوارەوە"],
        .motionFloat: ["Float in both directions", "طفو بالاتجاهين", "In beide Richtungen schweben", "Li her du aliyan bilive", "جووڵە بۆ هەردوو ئاراستە"],
        .respringHelp: ["Apply copies the selected wallpapers once. Nothing restarts automatically. Tap Respring when ready, then check the system wallpaper gallery.", "تطبيق بينسخ الخلفيات اللي اخترتها مرة وحدة. ما في إعادة تشغيل تلقائية. اكبس Respring لما تكون جاهز، وبعدين شوف معرض خلفيات النظام.", "Anwenden kopiert die ausgewählten Hintergründe einmal. Kein automatischer Neustart. Wenn bereit, Respring antippen und danach die Systemgalerie prüfen.", "Sepandin dîwarên hilbijartî carekê kopî dike. Rûkar bixwe ji nû ve dest pê nake. Dema amade bî Respring bitikîne û galeriya pergalê kontrol bike.", "جێبەجێکردن پاشبنەما هەڵبژێردراوەکان یەک جار کۆپی دەکات. هیچ شتێک خۆکارانە دەست پێناکاتەوە. کاتێک ئامادەیت Respring بدە و گەلەری سیستەم بپشکنە."],
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
        .animatedPhotos: ["Output: continuous photo motion. The preview shows layout only.", "الملف فيه حركة مستمرة للصور. المعاينة للترتيب بس.", "Ausgabe: dauerhafte Fotobewegung. Die Vorschau zeigt nur das Layout.", "Derketin: livîna domdar a wêneyan. Pêşdîtin tenê rêzê nîşan dide.", "دەرچوو جووڵەی بەردەوامی وێنەکانە. پێشبینین تەنها ڕێکخستن نیشان دەدات."],
        .staticPhotos: ["Output: static photos. Turn on floating for continuous motion.", "الملف صور ثابتة. شغّل الطفو إذا بدك حركة مستمرة.", "Ausgabe: statische Fotos. Für Dauerbewegung Schweben einschalten.", "Derketin: wêneyên sekinî. Ji bo livîna domdar herikînê veke.", "دەرچوو وێنەی جێگیرە. بۆ جووڵەی بەردەوام هەڵواسین چالاک بکە."],
        .effectsHelp: ["Effects are saved in the file. The preview shows layout only; system playback depends on iOS. New effects need verification on your device.", "التأثيرات بتنحفظ بالملف. المعاينة للترتيب بس والتشغيل حسب iOS. التأثيرات الجديدة بدها تأكد عالجهاز.", "Effekte werden in der Datei gespeichert. Vorschau zeigt nur das Layout; Wiedergabe hängt von iOS ab. Neue Effekte am Gerät prüfen.", "Bandor di pelê de tên tomarkirin. Pêşdîtin tenê rêzê ye; lêxistin bi iOS ve girêdayî ye. Bandorên nû li ser amûrê kontrol bike.", "کاریگەرییەکان لە فایلەکەدا پاشەکەوت دەکرێن. پێشبینین تەنها ڕێکخستنە؛ لێدان بە iOS بەستراوە. کاریگەرییە نوێکان لە ئامێر تاقی بکەوە."],
        .middle: ["Middle", "بالنص", "Mitte", "Navîn", "ناوەڕاست"],
        .zoom: ["Zoom", "تكبير", "Zoom", "Mezinkirin", "گەورەکردن"],
        .horizontal: ["Horizontal position", "المكان يمين ويسار", "Horizontale Position", "Cihê asoyî", "شوێنی ئاسۆیی"],
        .vertical: ["Vertical position", "المكان فوق وتحت", "Vertikale Position", "Cihê stûnî", "شوێنی ستوونی"],
        .describe: ["Describe your layout", "اكتب كيف بدك ياها", "Beschreibe dein Layout", "Bêje tu çawa dixwazî", "بنووسە چۆنی دەوێت"],
        .plan: ["Suggest layout (text only)", "اقترح ترتيب (نص بس)", "Layout vorschlagen (nur Text)", "Rêzê pêşniyar bike (tenê nivîs)", "پێشنیاری ڕێکخستن (تەنها دەق)"],
        .manualFallback: ["Layout suggestion unavailable. Your photos are unchanged; adjust them manually.", "الاقتراح مو متاح هلأ. صورك متل ما هي، فيك ترتّبها بإيدك.", "Layout-Vorschlag nicht verfügbar. Fotos unverändert; bitte manuell anpassen.", "Pêşniyara rêzê ne berdest e. Wêneyên te neguherîn; bi destan sererast bike.", "پێشنیاری ڕێکخستن بەردەست نییە. وێنەکانت نەگۆڕاون؛ بە دەست ڕێکیان بخە."],
        .title: ["Make a .tendies wallpaper", "اعمل خلفية .tendies", ".tendies-Hintergrund erstellen", "Dîwarê .tendies çêke", "دروستکردنی پاشبنەمای .tendies"],
        .steps: ["Pick photos or a video, preview, then generate. Save with Share or import into the gallery. Nothing is applied until you select a wallpaper and tap Apply below.", "اختار صور أو فيديو، شوف المعاينة وبعدين اعمل الملف. احفظه من المشاركة أو ضيفه للمعرض. ما بيتطبّق شي لحتى تختار الخلفية وتكبس تطبيق تحت.", "Fotos oder Video wählen, Vorschau prüfen und Datei erstellen. Über Teilen speichern oder in die Galerie importieren. Erst mit der Anwenden-Taste unten wird ein ausgewählter Hintergrund angewendet.", "Wêne an vîdyoyekê hilbijêre, pêşdîtinê bibîne û pelê çêke. Bi Parvekirinê tomar bike an têxe galeriyê. Heta ku tu dîwar hilnebijêrî û li jêr Sepandinê nebitikînî, tiştek nayê sepandin.", "وێنە یان ڤیدیۆ هەڵبژێرە، پێشبینین ببینە و فایل دروست بکە. بە هاوبەشکردن پاشەکەوتی بکە یان بیخە گەلەری. تا پاشبنەما هەڵنەبژێریت و دوگمەی جێبەجێکردنی خوارەوە نەدەیت، هیچ ناگۆڕێت."],
        .photos: ["Photos", "صور", "Fotos", "Wêne", "وێنە"],
        .video: ["Video", "فيديو", "Video", "Vîdyo", "ڤیدیۆ"],
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
