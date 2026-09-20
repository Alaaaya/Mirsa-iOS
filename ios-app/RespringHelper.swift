//
//  RespringHelper.swift
//  AirCard-iOS
//
//  Utilities for refreshing PosterBoard wallpaper collections and SpringBoard reloading.
//

import UIKit
import Foundation
import AirliftFFI

public final class RespringHelper: NSObject {

    /// Directly launches PosterBoard daemon so it re-reads custom descriptors
    @discardableResult
    public static func openPosterBoard() -> Bool {
        guard let obj = objc_getClass("LSApplicationWorkspace") as? NSObject else { return false }
        let workspace = obj.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject
        if let success = workspace?.perform(Selector(("openApplicationWithBundleID:")), with: "com.apple.PosterBoard") {
            return success != nil
        }
        return false
    }

    /// Reloads PosterBoard and opens Wallpaper settings
    public static func instantRespring() {
        openPosterBoard()
        reloadCollectionsViaLanguage()
        openWallpaperSettings()
    }

    /// Opens Settings › Wallpaper directly so the user can immediately choose newly injected collections
    public static func openWallpaperSettings() {
        for urlStr in ["prefs:root=WALLPAPER", "App-prefs:root=WALLPAPER", "prefs:root=Wallpaper", UIApplication.openSettingsURLString] {
            if let url = URL(string: urlStr) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
    }

    /// Opens Settings › General › Language & Region.
    /// Tapping the primary language and selecting Done immediately forces SpringBoard
    /// to reload with a spinning indicator without a full device reboot.
    public static func openLanguageSettings() {
        for urlStr in ["prefs:root=General&path=INTERNATIONAL", "App-prefs:root=General&path=INTERNATIONAL", UIApplication.openSettingsURLString] {
            if let url = URL(string: urlStr) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
    }

    /// Attempts to programmatically re-apply the system language to force a SpringBoard reload
    @discardableResult
    public static func reloadCollectionsViaLanguage() -> Bool {
        dlopen("/System/Library/PrivateFrameworks/SettingsFoundation.framework/SettingsFoundation", RTLD_NOW)
        dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_NOW)
        dlopen("/System/Library/PrivateFrameworks/InternationalSupport.framework/InternationalSupport", RTLD_NOW)

        guard let lang = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first else {
            return false
        }

        var langManager: NSObject? = nil
        if let obj = objc_getClass("IPSettingsUtilities") as? NSObject {
            langManager = obj
        } else if let obj = objc_getClass("PSLanguageSelector") as? NSObject {
            langManager = obj
        }

        if let manager = langManager, manager.responds(to: Selector(("setLanguage:"))) {
            _ = manager.perform(Selector(("setLanguage:")), with: lang)
            return true
        }

        return false
    }

    /// Triggers a clean device restart via Diagnostics Relay over the pairing tunnel
    public static func restartDevice(pairingPath: String) async -> Bool {
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>? = nil
                let rc = pairingPath.withCString { pC in
                    al_device_respring(pC, nil, nil, &outError)
                }
                if let p = outError {
                    al_string_free(p)
                }
                cont.resume(returning: rc == 0)
            }
        }
    }
}
