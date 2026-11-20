import SwiftUI

/// Flat dark palette shared by the project page and the install log. Plain colours only, no blur.
enum LCPalette {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.047)
    static let card = Color(red: 0.094, green: 0.094, blue: 0.102)
    static let cardStroke = Color(red: 0.141, green: 0.141, blue: 0.157)
    static let field = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let pill = Color(red: 0.173, green: 0.173, blue: 0.18)
    static let green = Color(red: 0.204, green: 0.78, blue: 0.349)
    static let signGreen = Color(red: 0.157, green: 0.655, blue: 0.271)
    static let cyan = Color(red: 0.353, green: 0.784, blue: 0.98)
    static let red = Color(red: 1, green: 0.271, blue: 0.227)
    static let versionBG = Color(red: 0.106, green: 0.176, blue: 0.243)
    static let versionText = Color(red: 0.247, green: 0.663, blue: 0.961)
    static let updateBG = Color(red: 0.11, green: 0.165, blue: 0.133)
    static let mint = Color(red: 0.306, green: 0.871, blue: 0.639)
    static let logBG = Color.black
}

/// One flat card: #18181A, radius 18, hairline border.
struct LCCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LCPalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LCPalette.cardStroke, lineWidth: 1))
    }
}
extension View { func lcCard() -> some View { modifier(LCCard()) } }

/// Full screen install log. Reads only the real state of the shared signing operation.
struct ProjectInstallLogView: View {
    @ObservedObject var signing: PersonalSigningOperation
    let projectID: UUID
    let appName: String
    let close: () -> Void
    @State private var confirmStop = false

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        ZStack {
            LCPalette.bg.ignoresSafeArea()
            if let state = signing.state, state.projectID == projectID {
                content(state)
            } else {
                Color.clear.onAppear { close() }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("mirsa.project.install-log")
    }

    private func title(_ state: PersonalSigningOperation.State) -> String {
        if state.running { return personalText("Processing", "جاري المعالجة") }
        return state.stage == .failed ? personalText("Not completed", "ما اكتملت العملية") : personalText("Completed", "اكتمل")
    }

    private func content(_ state: PersonalSigningOperation.State) -> some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "text.alignleft").font(.subheadline.weight(.semibold)).foregroundStyle(LCPalette.mint)
                    .frame(width: 40, height: 40).background(Color(red: 0.086, green: 0.157, blue: 0.137), in: Circle())
                Spacer()
                Text(title(state)).font(.headline)
                Spacer()
                Button { close() } label: {
                    Text(state.running ? personalText("In background", "في الخلفية") : personalText("Close", "إغلاق"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(LCPalette.mint)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Color(red: 0.078, green: 0.161, blue: 0.141), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("mirsa.project.install-log.close")
            }
            HStack(spacing: 12) {
                elapsed(state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PersonalSigningLabels.stage(state.stage)).font(.subheadline.weight(.bold))
                    Text(appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if state.running { ProgressView() }
                else if state.stage == .failed { Image(systemName: "xmark.circle.fill").foregroundStyle(LCPalette.red) }
                else { Image(systemName: "checkmark.circle.fill").foregroundStyle(LCPalette.green) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LCPalette.pill)
                    Capsule().fill(state.stage == .failed ? LCPalette.red : LCPalette.mint)
                        .frame(width: geo.size.width * (state.running ? state.overallFraction : (state.stage == .failed ? 1 : 1)))
                }
            }.frame(height: 3)
            logList(state)
            if state.running {
                Button { confirmStop = true } label: {
                    Text(personalText("Stop", "إيقاف")).font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 0.898, green: 0.282, blue: 0.302))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color(red: 0.212, green: 0.086, blue: 0.09), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("mirsa.project.install-log.stop")
                Text(PersonalSigningLabels.weighted).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if state.stage == .handedOff {
                Text(personalText("Handed off to the iOS installer. iOS finishes the installation; Mirsa cannot confirm it.", "انسلّم التثبيت لنظام iOS. النظام بيكمل التثبيت وMirsa ما بيقدر يأكده."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .confirmationDialog(personalText("Stop signing?", "إيقاف التوقيع؟"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(personalText("Stop", "إيقاف"), role: .destructive) { signing.stop() }
            Button(personalText("Keep going", "كمّل"), role: .cancel) {}
        }
    }

    @ViewBuilder private func elapsed(_ state: PersonalSigningOperation.State) -> some View {
        if state.running {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Self.mmss(ctx.date.timeIntervalSince(state.startedAt)))
            }.font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        } else {
            Text(Self.mmss((state.log.last?.time ?? state.startedAt).timeIntervalSince(state.startedAt)))
                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    private static func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(t)); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func logList(_ state: PersonalSigningOperation.State) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(state.log) { line in
                        (Text(Self.clock.string(from: line.time) + " " + line.level + " ").foregroundStyle(.secondary)
                            + Text(line.source + " ").foregroundStyle(line.level == "E" ? LCPalette.red : (line.level == "W" ? Color.orange : LCPalette.mint))
                            + Text(line.text).foregroundStyle(Color.white.opacity(0.9)))
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }.padding(12)
            }
            .background(LCPalette.logBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: state.log.count) { _ in
                if let last = state.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
