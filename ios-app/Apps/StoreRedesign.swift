import SwiftUI
import UIKit
import ImageIO

// MARK: - App Store section redesign: shared look (UI only)
//
// Pure presentation helpers for the «متجر أبل» section: Mirsa identity colours,
// layered glass, icon-tinted cards, chips, skeletons, empty states, flags,
// initials and light haptics. Nothing here signs in, buys, downloads or installs;
// callers pass the existing actions in as closures.

/// Five-language text for the redesigned store section, through the app's own
/// language setting (AppLanguageStore). German is used when the app language is Deutsch.
func storeText(_ en: String, _ ar: String, de: String, ckb: String, kmr: String) -> String {
    StoreFeatureText.t(en, ar, de, ckb, kmr)
}

// MARK: Identity

enum StoreLuxe {
    /// Mirsa violet, the section's identity colour.
    static let accent = MirsaPalette.accent
    static let accentSoft = MirsaPalette.accentSoft
    static let cyan = Color(red: 0.36, green: 0.84, blue: 0.98)
    static let indigo = Color(red: 0.33, green: 0.47, blue: 1.0)

    static var identity: LinearGradient {
        LinearGradient(colors: [accent, indigo, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var identitySoft: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.55), indigo.opacity(0.35), cyan.opacity(0.25)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Queue state colours.
    static let loading = Color(red: 0.36, green: 0.70, blue: 1.0)
    static let ready = MirsaPalette.accentSoft
    static let done = MirsaPalette.success
    static let failed = MirsaPalette.danger

    /// Stable colour from text (FNV-1a), for cards whose icon is not loaded yet.
    static func seedColor(_ seed: String) -> Color {
        var hash: UInt32 = 2166136261
        for b in seed.utf8 { hash = (hash ^ UInt32(b)) &* 16777619 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.62, brightness: 0.78)
    }

    /// Keeps an icon's average colour readable as a card background.
    /// Pre-tinted glass fill used instead of a per-card blur (close to ultraThinMaterial on the aurora).
    static let glassTop = Color(red: 0.20, green: 0.19, blue: 0.34).opacity(0.62)
    static let glassBottom = Color(red: 0.11, green: 0.10, blue: 0.22).opacity(0.70)

    static func vivid(_ color: Color) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        return Color(hue: Double(h), saturation: Double(min(1, max(0.38, s * 1.2))), brightness: Double(min(0.86, max(0.48, b))))
    }
}

// MARK: Layered glass

/// Layered glass with the Mirsa rim and a soft top sheen.
///
/// Performance: cards and chips draw a pre-tinted translucent fill instead of a live blur,
/// so scrolling lists composite flat layers only. A real `.ultraThinMaterial` is kept for
/// one region per screen (the floating bar, `material: true`). Only raised surfaces
/// (elevation >= 1.2: the bar and hero cards, a few per screen) get a single soft shadow,
/// drawn by the base shape alone. Classic theme or Reduce Transparency draws the solid card.
struct StoreGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var sheen = true
    var elevation: Double = 1
    var material = false
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let liquid = theme == MirsaTheme.liquid.rawValue && !reduceTransparency
        let tone = tint ?? StoreLuxe.accent
        content
            .background {
                ZStack {
                    base(liquid: liquid)
                    if liquid {
                        shape.fill(LinearGradient(colors: [tone.opacity(tint == nil ? 0.16 : 0.34), Color.white.opacity(0.02)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        shape.fill(LinearGradient(colors: [tone.opacity(tint == nil ? 0.14 : 0.32), tone.opacity(0.04)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    if sheen {
                        shape.fill(LinearGradient(stops: [
                            .init(color: Color.white.opacity(liquid ? 0.14 : 0.07), location: 0),
                            .init(color: Color.white.opacity(0), location: 0.45),
                        ], startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.30), tone.opacity(0.28), Color.white.opacity(0.04)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
            }
            .contentShape(shape)
    }

    @ViewBuilder private func base(liquid: Bool) -> some View {
        if elevation >= 1.2 {
            fill(liquid: liquid).shadow(color: Color.black.opacity(0.26), radius: 10, y: 5)
        } else {
            fill(liquid: liquid)
        }
    }

    @ViewBuilder private func fill(liquid: Bool) -> some View {
        Group {
            if liquid && material {
                shape.fill(.ultraThinMaterial)
            } else if liquid {
                // Pre-tinted stand-in for the material: same dark violet glass, no blur pass.
                shape.fill(LinearGradient(colors: [StoreLuxe.glassTop, StoreLuxe.glassBottom], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(LinearGradient(colors: [MirsaPalette.cardTop, MirsaPalette.card], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

extension View {
    func storeGlass(radius: CGFloat = 24, tint: Color? = nil, sheen: Bool = true, elevation: Double = 1) -> some View {
        modifier(StoreGlass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, sheen: sheen, elevation: elevation))
    }
    func storeGlassCapsule(tint: Color? = nil, elevation: Double = 0.6) -> some View {
        modifier(StoreGlass(shape: Capsule(), tint: tint, elevation: elevation))
    }
    /// The one live-blur region of a screen: the floating section bar.
    func storeGlassBar(elevation: Double = 1.2) -> some View {
        modifier(StoreGlass(shape: Capsule(), elevation: elevation, material: true))
    }
}

/// Section background: the app's themed aurora with a faint Mirsa glow on top.
/// Reduce Motion, or a page that is hidden behind another one, freezes the drifting light.
struct StoreLuxeBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.storePageVisible) private var pageVisible
    var body: some View {
        ZStack {
            AuroraBackground(paused: reduceMotion || !pageVisible)
            RadialGradient(colors: [StoreLuxe.accent.opacity(0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [StoreLuxe.cyan.opacity(0.10), .clear], center: .bottomLeading, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct StoreBackdropProvidedKey: EnvironmentKey { static let defaultValue = false }
private struct StorePageVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// False for the App Store pages kept alive but hidden, so their animations rest.
    var storePageVisible: Bool {
        get { self[StorePageVisibleKey.self] }
        set { self[StorePageVisibleKey.self] = newValue }
    }
    /// Set by the App Store tab, which draws one shared background behind all four pages.
    var storeBackdropProvided: Bool {
        get { self[StoreBackdropProvidedKey.self] }
        set { self[StoreBackdropProvidedKey.self] = newValue }
    }
}

/// A page's background: nothing when the tab already draws the shared one (so hidden pages
/// do not keep extra animated auroras alive), the full background when hosted on its own.
struct StorePageBackdrop: View {
    @Environment(\.storeBackdropProvided) private var provided
    var body: some View {
        if provided { Color.clear.allowsHitTesting(false) } else { StoreLuxeBackground() }
    }
}

// MARK: Haptics

@MainActor
enum StoreHaptics {
    static func get() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.75) }
    static func install() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8) }
    static func delete() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: Icon colour

struct StoreArtworkDecoded: @unchecked Sendable {
    let image: UIImage
    let color: Color
}

/// Off-main image work: download, downsample with ImageIO and average colour.
enum StoreArtworkDecoder {
    static func decode(_ url: URL) async -> StoreArtworkDecoded? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 360] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return StoreArtworkDecoded(image: UIImage(cgImage: cg), color: StoreLuxe.vivid(average(cg)))
    }

    /// Average colour from a 1x1 redraw. Safe off the main thread.
    static func average(_ cg: CGImage) -> Color {
        let fallback = Color(red: 0.45, green: 0.35, blue: 0.95)
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let raw = ctx.data else { return fallback }
        let p = raw.assumingMemoryBound(to: UInt8.self)
        return Color(red: Double(p[0]) / 255, green: Double(p[1]) / 255, blue: Double(p[2]) / 255)
    }
}

/// Loads public App Store artwork once per URL and keeps its dominant (average) colour.
/// Images live in an NSCache (not published), so a finished download only redraws the
/// one icon that asked for it; colour updates are coalesced into one publish per burst.
@MainActor
final class StoreArtworkTint: ObservableObject {
    static let shared = StoreArtworkTint()
    @Published private(set) var colors: [String: Color] = [:]
    private let images: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()
    private var inflight: [String: Task<StoreArtworkDecoded?, Never>] = [:]
    private var pending: [String: Color] = [:]
    private var flushScheduled = false

    func cachedImage(_ urlString: String) -> UIImage? { images.object(forKey: urlString as NSString) }

    func load(_ urlString: String) async -> UIImage? {
        if let hit = cachedImage(urlString) { return hit }
        guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme == "https" else { return nil }
        let task: Task<StoreArtworkDecoded?, Never>
        if let running = inflight[urlString] { task = running }
        else {
            task = Task.detached(priority: .utility) { await StoreArtworkDecoder.decode(url) }
            inflight[urlString] = task
        }
        let result = await task.value
        inflight[urlString] = nil
        guard let result else { return nil }
        images.setObject(result.image, forKey: urlString as NSString)
        if colors[urlString] == nil && pending[urlString] == nil { enqueue(urlString, result.color) }
        return result.image
    }

    private func enqueue(_ key: String, _ color: Color) {
        pending[key] = color
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            if self.colors.count > 300 { self.colors.removeAll() }
            self.colors.merge(self.pending) { _, new in new }
            self.pending.removeAll()
            self.flushScheduled = false
        }
    }

    func tint(_ urlString: String, seed: String) -> Color {
        colors[urlString] ?? StoreLuxe.seedColor(seed)
    }
}

/// Average colour of local IPA icons, computed once per key off the main thread.
@MainActor
enum StoreIconTintCache {
    private static var colors: [String: Color] = [:]
    private struct Box: @unchecked Sendable { let image: CGImage }

    static func cached(_ key: String) -> Color? { colors[key] }

    static func color(_ key: String, image: UIImage?) async -> Color? {
        if let hit = colors[key] { return hit }
        guard let cg = image?.cgImage else { return nil }
        let box = Box(image: cg)
        let c = await Task.detached(priority: .utility) { StoreLuxe.vivid(StoreArtworkDecoder.average(box.image)) }.value
        colors[key] = c
        return c
    }
}

/// App icon from artwork, with a tinted monogram while loading. Only this icon redraws
/// when its image arrives. A shadow is drawn for the large hero icon only.
struct StoreArtwork: View {
    let url: String
    let seed: String
    let name: String
    var size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            if let image = image ?? StoreArtworkTint.shared.cachedImage(url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [StoreLuxe.seedColor(seed), StoreLuxe.seedColor(seed + "~").opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
        .background {
            if size >= 100 { shape.fill(Color.black.opacity(0.35)).shadow(color: .black.opacity(0.3), radius: 8, y: 5) }
        }
        .task(id: url) {
            if let hit = StoreArtworkTint.shared.cachedImage(url) { image = hit; return }
            image = await StoreArtworkTint.shared.load(url)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Account identity

enum StoreIdentity {
    /// Up to two initials from the name, else from the email's local part.
    static func initials(name: String, email: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? (email.split(separator: "@").first.map(String.init) ?? "") : trimmed
        let parts = source.split(whereSeparator: { " ._-+".contains($0) }).filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    /// Regional indicator flag for a two-letter storefront, a globe otherwise.
    static func flag(_ code: String) -> String {
        let upper = code.uppercased()
        guard upper.count == 2, upper.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "🌐" }
        var out = String.UnicodeScalarView()
        for s in upper.unicodeScalars { if let f = UnicodeScalar(127397 + s.value) { out.append(f) } }
        return String(out)
    }
}

/// Monogram avatar ring in the identity gradient.
struct StoreMonogram: View {
    let name: String
    let email: String
    var size: CGFloat = 56
    var body: some View {
        let initials = StoreIdentity.initials(name: name, email: email)
        ZStack {
            Circle().fill(StoreLuxe.identity)
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
            if email.isEmpty && name.isEmpty {
                Image(systemName: "person.fill").font(.system(size: size * 0.40)).foregroundStyle(.white)
            } else {
                Text(initials).font(.system(size: size * (initials.count > 1 ? 0.36 : 0.44), weight: .bold, design: .rounded))
                    .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2))
        .background(Circle().fill(StoreLuxe.accent.opacity(0.35)).padding(-size * 0.06))
        .accessibilityHidden(true)
    }
}

// MARK: Chips and layout

/// Wrapping row layout for chips.
struct StoreFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Glass chip with an optional leading symbol.
struct StoreChip: View {
    let title: String
    var icon: String? = nil
    var selected = false
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(title).lineLimit(1).truncationMode(.tail)
        }
        .font(MirsaFont.caption.weight(.semibold))
        .foregroundStyle(selected ? Color.white : MirsaPalette.textSecondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: 220)
        .background {
            if selected { Capsule().fill(StoreLuxe.identity).opacity(0.85) }
        }
        .storeGlassCapsule(tint: selected ? StoreLuxe.accent : nil, elevation: 0.3)
    }
}

/// Small coloured state badge for the queue.
struct StoreStateBadge: View {
    let title: String
    let color: Color
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            else { Circle().fill(color).frame(width: 6, height: 6) }
            Text(title).lineLimit(1)
        }
        .font(MirsaFont.badge)
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.8))
    }
}

/// Section title with a small accent bar, used by every page of the section.
struct StoreSectionTitle: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(StoreLuxe.identity).frame(width: 4, height: 16)
            Text(title).font(MirsaFont.sectionTitle).foregroundStyle(.white)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Large page title with the section's glow and an optional trailing control.
struct StorePageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: MirsaSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2)
                        .foregroundStyle(StoreLuxe.identity)
                        .lineLimit(1)
                }
                Text(title)
                    .font(MirsaFont.pageTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: MirsaSpacing.xs)
            trailing()
        }
        .padding(.top, MirsaSpacing.s)
    }
}

// MARK: Empty and loading

/// Polished empty state: glowing orb, title, message and an optional action.
struct StoreEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: MirsaSpacing.s) {
            ZStack {
                Circle().fill(RadialGradient(colors: [StoreLuxe.accent.opacity(0.55), StoreLuxe.cyan.opacity(0.18), .clear],
                                             center: .center, startRadius: 20, endRadius: 62))
                    .frame(width: 124, height: 124)
                Circle().fill(StoreLuxe.identity).frame(width: 64, height: 64)
                    .overlay(Circle().fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.bottom, 4)
            Text(title).font(MirsaFont.cardTitle).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(message).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(MirsaFont.button).foregroundStyle(.white)
                        .padding(.horizontal, 20).frame(height: 40)
                        .background(StoreLuxe.identity, in: Capsule())
                }
                .buttonStyle(.mirsaPress)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, MirsaSpacing.xl).padding(.horizontal, MirsaSpacing.l)
        .frame(maxWidth: .infinity)
        .storeGlass(radius: 28)
    }
}

/// Shimmering placeholder block. The UI-test harness keeps it still so XCUITest can idle.
struct StoreShimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: g.size.width * phase)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !MirsaUITestHarness.active, !reduceMotion else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// Skeleton of one app card while results or history load.
struct StoreSkeletonCard: View {
    var iconSize: CGFloat = 60
    var body: some View {
        HStack(spacing: MirsaSpacing.s) {
            RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous).fill(Color.white.opacity(0.10))
                .frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Color.white.opacity(0.12)).frame(width: 150, height: 12)
                Capsule().fill(Color.white.opacity(0.08)).frame(width: 100, height: 9)
                Capsule().fill(Color.white.opacity(0.07)).frame(width: 64, height: 9)
            }
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.10)).frame(width: 64, height: 32)
        }
        .padding(MirsaSpacing.card)
        .modifier(StoreShimmer())
        .storeGlass(radius: 24, sheen: false, elevation: 0.4)
        .accessibilityHidden(true)
    }
}

// MARK: Storage

/// Space used by imported/downloaded IPA files, read from local file sizes only.
struct StoreStorageSummary: View {
    struct Slice: Identifiable { let id: UUID; let name: String; let bytes: Int64; let color: Color }
    let slices: [Slice]
    let total: Int64
    let free: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(storeText("IPA storage", "مساحة ملفات IPA", de: "IPA-Speicher", ckb: "شوێنی IPA", kmr: "Cihê IPA"))
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    Text(StoreBytes.text(total))
                        .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(slices.count) " + storeText("files", "ملفات", de: "Dateien", ckb: "فایل", kmr: "pel"))
                        .font(MirsaFont.secondary.weight(.semibold)).foregroundStyle(MirsaPalette.textSecondary).monospacedDigit()
                    if let free {
                        Text(storeText("Free on iPhone: ", "الفاضي بالآيفون: ", de: "Frei auf dem iPhone: ", ckb: "بەتاڵ لە ئایفۆن: ", kmr: "Vala li iPhone: ")
                             + StoreBytes.text(free))
                            .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    if total <= 0 {
                        Capsule().fill(Color.white.opacity(0.08))
                    } else {
                        ForEach(slices.prefix(6)) { s in
                            Rectangle().fill(s.color)
                                .frame(width: max(3, g.size.width * CGFloat(Double(s.bytes) / Double(total)) - 2))
                        }
                        Rectangle().fill(Color.white.opacity(0.10))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            if !slices.isEmpty {
                StoreFlowLayout(spacing: 10) {
                    ForEach(slices.prefix(4)) { s in
                        HStack(spacing: 5) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.name).lineLimit(1)
                            Text(StoreBytes.text(s.bytes)).foregroundStyle(MirsaPalette.textTertiary)
                        }
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                        .frame(maxWidth: 200, alignment: .leading)
                    }
                }
            }
        }
        .padding(MirsaSpacing.card)
        .storeGlass(radius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("store-storage-summary")
    }
}

enum StoreBytes {
    /// File size text with digits always ("0 KB", never "Zero KB").
    static func text(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: max(0, bytes))
    }
}

enum StoreStorageReader {
    /// Real on-disk size of each saved IPA (FileManager attributes only) and the free capacity.
    static func read(_ entries: [EncryptedIPAEntry]) async -> (sizes: [UUID: Int64], free: Int64?) {
        let ids = entries.map(\.id)
        return await Task.detached(priority: .utility) {
            var sizes: [UUID: Int64] = [:]
            for id in ids {
                let url = EncryptedAppsStore.ipaURL(id)
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) {
                    sizes[id] = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                }
            }
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
            return (sizes, free)
        }.value
    }
}

// MARK: Sharing

enum StoreLinks {
    /// Public App Store page for an app ID in a storefront.
    static func appPage(id: Int64, country: String) -> URL? {
        guard id > 0 else { return nil }
        let cc = country.lowercased().filter { $0.isLetter }.prefix(2)
        return URL(string: "https://apps.apple.com/\(cc.isEmpty ? "us" : String(cc))/app/id\(id)")
    }
    @MainActor static func copy(_ text: String) {
        UIPasteboard.general.string = text
        StoreHaptics.select()
    }
}

// MARK: Page transitions

extension View {
    /// Smooth cross-fade with a slight lift for the section's pages (cross-fade only with Reduce Motion).
    func storePageTransition(visible: Bool) -> some View {
        modifier(StorePageTransition(visible: visible))
    }
}

private struct StorePageTransition: ViewModifier {
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.985, anchor: .bottom)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86), value: visible)
    }
}

// MARK: Fixtures (DEBUG screenshots only)

#if DEBUG
enum StoreRedesignFixtures {
    static var purchases: [MirsaStorePurchase] {
        let now = Date()
        func ago(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now }
        return [
            MirsaStorePurchase(id: 100001, bundleID: "com.example.notes", name: "Notes Pro", version: "5.2.1", date: ago(3)),
            MirsaStorePurchase(id: 100002, bundleID: "com.example.weather", name: "Weather Live", version: "2.0", date: ago(9)),
            MirsaStorePurchase(id: 100004, bundleID: "com.example.photos", name: "Photo Lab", version: "8.1", date: ago(38)),
            MirsaStorePurchase(id: 100005, bundleID: "com.example.maps", name: "Trail Maps", version: "1.9", date: ago(44)),
            MirsaStorePurchase(id: 100006, bundleID: "com.example.focus", name: "Focus Timer", version: "3.0", date: ago(75)),
            MirsaStorePurchase(id: 100003, bundleID: "com.example.studio", name: "Music Studio", version: "3.4", date: ago(130)),
        ]
    }
}
#endif

// MARK: List rows

/// Clear, separator-free List row so glass cards float on the section background.
struct StoreListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: MirsaSpacing.page, bottom: 6, trailing: MirsaSpacing.page))
    }
}
