import Foundation

/// Per-project signing options consumed by PersonalCertificateSigner.sign.
struct PersonalProjectOptions: Sendable {
    var attemptID = UUID()
    var draftRevision: String? = nil
    var selectedComponentIDs: [String] = []
    var displayName: String? = nil
    var bundleID: String? = nil
    var version: String? = nil
    var outputFilename: String = "Mirsa-Signed"
    var fileSharing = true
    var removeURLSchemes = false
    var removeEmbeddedProfile = false
    var removeWatchApp = false
    var minimumOS: String? = nil
    var libraries: [URL] = []
    /// When non-empty, per-component target plan (inject_plan) replaces plain library injection.
    var injections: [InjectionPlanEntry] = []
    /// Staged file-manager edits applied to the workspace copy right after extraction (before every other edit).
    var bundleOverlay: BundleOverlay? = nil
    var bundleBlobs: URL? = nil
    var bundleOriginal: URL? = nil
    var injectionOrder: [String] = []
    var existingLibraryEdits: [ExistingLibraryEdit] = []
    var additionalProfiles: [Data] = []
    var removeExtensions = false
    var removeAppClips = false
    var strictProfile = false
    var gameMode: PersonalGameMode = .keep
    var fixDarkIcon = true
    var fixWhiteIcon = false
    var newTweaksFirst = false
    var useLoader = true
    var iconPNG: Data? = nil
    var customEntitlements: Data? = nil
    var exportExtension = "ipa"
    /// Explicit opt-in: strips UIDeviceFamily, MinimumOSVersion and UIRequiredDeviceCapabilities from the project COPY.
    var removeDeviceRestrictions = false
    /// Opt-in generic runtime Arabic dictionary and missing-only online grant on a separate signing copy.
    var backgroundNotifications = false
    var backgroundMethods: [BackgroundNotificationMethod] = []
    var translateToArabic = false

    /// Copy the optional persisted choice into this attempt, never retain a live draft.
    mutating func applyTranslationChoice(from draft: PersonalProjectDraft, originalBundleID: String? = nil) {
        translateToArabic = draft.translateArabic ?? originalBundleID.map { ArabicTranslatePrefs.isOn($0) } ?? false
    }
}

enum PersonalGameMode: String, Codable, CaseIterable, Sendable { case keep, on, off }

func personalText(_ en: String, _ ar: String) -> String { MirsaTr.pick(en, ar) }

/// Editable values persisted per library app. Library files are referenced by id,
/// never by absolute path.
struct PersonalProjectDraft: Codable, Equatable {
    var name = ""
    var bundleID = ""
    var version = ""
    var outputFilename = ""
    var fileSharing = true
    var removeURLSchemes = false
    var removeEmbeddedProfile = false
    var removeWatchApp = false
    var minimumOS = ""
    var tweakIDs: [UUID] = []
    var removeExtensions: Bool? = nil
    var removeAppClips: Bool? = nil
    var translateArabic: Bool? = nil
    /// Optional keys use synthesized decodeIfPresent. Old projects remain off.
    var backgroundNotifications: Bool? = nil
    var backgroundAudio: Bool? = nil
    var backgroundLocation: Bool? = nil
    var strictProfile: Bool? = nil
    var additionalProfileIDs: [String]? = nil
    var gameMode: PersonalGameMode? = nil
    var fixWhiteIcon: Bool? = nil
    /// New projects opt in after native catalog proof; missing legacy key stays nil (off).
    var fixDarkIcon: Bool? = true
    var newTweaksFirst: Bool? = nil
    var workspaceNote: String? = nil
    var exportExtension: String? = nil
    var iconPNG: Data? = nil
    var customEntitlements: Data? = nil
    var customEntitlementsName: String? = nil
    var directInjection: Bool? = false
    /// component id (uuid:path) -> InjectionMethod raw value. Absent = migrate from legacy directInjection.
    var injectionMethods: [String: String]? = nil
    /// component id -> selected process target ids for separate_extension (decoded optional, backward compatible).
    var injectionProcessTargets: [String: [String]]? = nil
    /// component id -> backend shared candidate id for shared_library.
    var injectionSharedTargets: [String: String]? = nil
    /// tweak id -> target id. nil/absent = main executable. Specific framework/extension targets stay disabled until the backend enumerates real Mach-O targets.
    var tweakTargets: [String: String]? = nil
    /// Excluded package components, keyed "<tweakUUID>:<rootRelativePath>". A .deb exposes each dylib/framework root as its own component.
    var excludedRoots: [String]? = nil
    /// Ordered stable component ids (uuid:path). Drives per-component load order.
    var componentOrder: [String]? = nil
    /// Staged bundle file edits (rename/delete/import/plist) made in the file manager.
    var bundleOverlay: BundleOverlay? = nil
    var appliedTweakIDs: [UUID]? = nil
    var existingLibraryEdits: [ExistingLibraryEdit]? = nil
}

/// Original IPA dependency provenance, not an assertion that a dependency was injected.
struct ExistingProjectLibrary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let owner: String
    let loadPath: String
    let kind: String
    let bundledPath: String?
    let provenance: String
    let slices: [String]
}
/// Reset means clearing this plan. Original IPA bytes are never modified.
struct ExistingLibraryEdit: Codable, Equatable, Sendable {
    var owner: String
    var removed: [String] = []
    var order: [String] = []
    /// Optional so plans saved before disable support still decode.
    var disabled: [String]? = nil
}

/// Shared copy for the certificate-only option and its recoverable device warning.
enum PersonalProfileOmissionText {
    static func title(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "Remove mobileprovision after signing"
        case .arabic: return "إزالة mobileprovision بعد التوقيع"
        case .german: return "mobileprovision nach dem Signieren entfernen"
        case .kurmanji: return "Piştî îmzekirinê mobileprovision rake"
        case .sorani: return "سڕینەوەی mobileprovision دوای واژۆکردن"
        }
    }
    static func subtitle(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "Hides the profile from the app. The profile must already be installed on the device; Mirsa tries to install it when connected."
        case .arabic: return "بيخفي البروفايل من التطبيق. لازم يكون مثبّت عالجهاز؛ مرسى بيحاول يثبّته إذا الجهاز متصل."
        case .german: return "Entfernt das Profil aus der App. Es muss bereits auf dem Gerät installiert sein; bei bestehender Verbindung versucht Mirsa es zu installieren."
        case .kurmanji: return "Profîlê ji appê vedişêre. Divê profîl berê li ser cîhazê hatibe sazkirin; dema girêdanê Mirsa hewl dide wê saz bike."
        case .sorani: return "پرۆفایل لە ئەپەکە دەشارێتەوە. دەبێت پێشتر لەسەر ئامێرەکە دامەزرابێت؛ مرسى لە کاتی پەیوەندی هەوڵی دامەزراندنی دەدات."
        }
    }
    static func deviceWarning(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "Mirsa could not install the profile on the device. Install it separately before installing this profile-free app."
        case .arabic: return "مرسى ما قدر يثبّت البروفايل عالجهاز. ثبّته بشكل منفصل قبل تثبيت هالتطبيق الخالي من البروفايل."
        case .german: return "Mirsa konnte das Profil nicht auf dem Gerät installieren. Installiere es separat, bevor du diese App ohne eingebettetes Profil installierst."
        case .kurmanji: return "Mirsa nekarî profîlê li ser cîhazê saz bike. Berî sazkirina vê appa bê profîl, profîlê cuda saz bike."
        case .sorani: return "مرسى نەیتوانی پرۆفایلەکە لەسەر ئامێرەکە دابمەزرێنێت. پێش دامەزراندنی ئەم ئەپە بێ پرۆفایلە، پرۆفایلەکە بە جیا دابمەزرێنە."
        }
    }
}
