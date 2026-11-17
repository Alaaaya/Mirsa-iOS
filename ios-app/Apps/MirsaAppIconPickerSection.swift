import SwiftUI
import UIKit

/// A Settings-only picker. The system's actual selection is the source of truth.
struct MirsaAppIconPickerSection: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var errorMessage: String?

    private func text(_ en: String, _ ar: String, _ de: String, _ kmr: String, _ ckb: String) -> String {
        // Also handles German stored by newer clients without expanding the app's language enum.
        if UserDefaults.standard.string(forKey: AppLanguageStore.key) == "de" { return de }
        switch language.current {
        case .german: return de
        case .english: return en
        case .arabic: return ar
        case .kurmanji: return kmr
        case .sorani: return ckb
        }
    }

    private var title: String { text("App icon", "أيقونة التطبيق", "App-Symbol", "Îkona sepanê", "ئایکۆنی ئەپ") }
    private var currentLabel: String { text("Selected", "مختارة", "Ausgewählt", "Hilbijartî", "هەڵبژێردراو") }
    private func name(_ index: Int) -> String {
        index == 0
            ? text("Original", "الأصلية", "Original", "Resen", "ڕەسەن")
            : text("Icon", "أيقونة", "Symbol", "Îkon", "ئایکۆن") + " \(index)"
    }
    private func iconName(_ index: Int) -> String? { index == 0 ? nil : "MirsaIcon\(index)" }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(text("Choose how Mirsa looks on your Home Screen. iOS confirms each change.",
                          "اختار شكل مرسى عالشاشة الرئيسية. iOS بيعرض تنبيه بعد كل تغيير.",
                          "Wähle Mirsas Symbol auf dem Home-Bildschirm. iOS bestätigt jede Änderung.",
                          "Dîmena Mirsayê li ser ekrana sereke hilbijêre. iOS her guhertinê piştrast dike.",
                          "شێوەی میرسە لەسەر شاشەی سەرەکی هەڵبژێرە. iOS هەر گۆڕانێک پشتڕاست دەکاتەوە."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(0..<7) { index in
                        iconButton(index)
                    }
                }
                if changing { ProgressView().frame(maxWidth: .infinity) }
                if !UIApplication.shared.supportsAlternateIcons {
                    Text(text("Changing icons is not available on this device.", "تغيير الأيقونة مو متاح بهالجهاز.",
                              "Auf diesem Gerät lassen sich Symbole nicht ändern.", "Guhertina îkonê li ser vê amûrê ne berdest e.",
                              "گۆڕینی ئایکۆن لەم ئامێرەدا بەردەست نییە."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(MirsaPalette.danger)
                        .accessibilityIdentifier("mirsa.icon.error")
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text(title)
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func iconButton(_ index: Int) -> some View {
        let isSelected = selected == iconName(index)
        return Button {
            change(to: iconName(index))
        } label: {
            VStack(spacing: 7) {
                Image("MirsaIconPreview\(index)")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, MirsaPalette.accent)
                                .font(.system(size: 23, weight: .semibold))
                                .background(Circle().fill(MirsaPalette.row).padding(2))
                                .offset(x: 5, y: 5)
                        }
                    }
                Text(name(index))
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? MirsaPalette.accentSoft : MirsaPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(changing || !UIApplication.shared.supportsAlternateIcons)
        .accessibilityLabel(name(index))
        .accessibilityValue(isSelected ? currentLabel : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("mirsa.icon.\(index)")
    }

    private func refresh() { selected = UIApplication.shared.alternateIconName }

    private func change(to name: String?) {
        guard !changing, UIApplication.shared.supportsAlternateIcons, selected != name else { return }
        changing = true
        errorMessage = nil
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                changing = false
                refresh()
                if error != nil {
                    errorMessage = text("Couldn’t change the icon. Please try again.", "ما قدرت غيّر الأيقونة. جرّب مرة تانية.",
                                        "Das Symbol konnte nicht geändert werden. Bitte erneut versuchen.",
                                        "Îkon nehat guhertin. Ji kerema xwe dîsa biceribîne.",
                                        "نەتوانرا ئایکۆنەکە بگۆڕدرێت. تکایە دووبارە هەوڵ بدەوە.")
                }
            }
        }
    }
}
