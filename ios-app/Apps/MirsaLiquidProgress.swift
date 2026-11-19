import SwiftUI

/// Original Canvas artwork. No third-party shader, assets, or code.
/// The caller remains the sole authority for measured progress and completion.
struct MirsaLiquidProgress: View {
    var value: Double? = nil
    var diameter: CGFloat = 68
#if DEBUG
    // EnvironmentValues.accessibilityReduceMotion is read-only. Keep the
    // deterministic review override local to this component and DEBUG builds.
    var reviewReduceMotion: Bool? = nil
#endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var fraction: Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }
    private var effectiveReduceMotion: Bool {
#if DEBUG
        reviewReduceMotion ?? reduceMotion
#else
        reduceMotion
#endif
    }

    var body: some View {
        Group {
            if effectiveReduceMotion {
                ProgressView(value: fraction).progressViewStyle(.linear)
                    .frame(maxWidth: 180).tint(.purple)
            } else {
                TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 15 : 1.0 / 60,
                                        paused: scenePhase != .active || fraction == 1 || MirsaUITestHarness.active)) { timeline in
                    let time = MirsaUITestHarness.active ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Canvas { context, size in
                            drawOrb(context: context, size: size, time: time)
                        }
                        if let fraction, diameter >= 36 {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: diameter * 0.22, weight: .bold, design: .rounded))
                                .monospacedDigit().foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 3)
                        } else {
                            Image(systemName: "ellipsis").foregroundStyle(.white)
                        }
                    }
                    .frame(width: diameter, height: diameter)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(PersonalSigningLabels.text("Progress", "التقدّم", "پێشکەوتن", "Pêşveçûn")))
        .accessibilityValue(fraction.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("…"))
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func drawOrb(context: GraphicsContext, size: CGSize, time: Double) {
        var c = context
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
        let shell = Path(ellipseIn: rect)
        c.fill(shell, with: .radialGradient(Gradient(colors: [
            .white.opacity(0.2), Color(red: 0.13, green: 0.08, blue: 0.24).opacity(0.9)
        ]), center: CGPoint(x: size.width * 0.3, y: size.height * 0.2), startRadius: 0, endRadius: size.width))
        c.clip(to: shell)
        let f = fraction ?? 0.45
        let level = rect.maxY - rect.height * f
        let amplitude = sin(.pi * f) * rect.height * 0.035
        for layer in 0..<2 {
            var liquid = Path()
            liquid.move(to: CGPoint(x: rect.minX, y: rect.maxY + 2))
            for step in 0...48 {
                let x = rect.minX + rect.width * Double(step) / 48
                let phase = x / rect.width * .pi * 2 + time * 1.7 + Double(layer) * 2
                let y = level + sin(phase) * amplitude + Double(layer) * 2
                liquid.addLine(to: CGPoint(x: x, y: y))
            }
            liquid.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 2))
            liquid.closeSubpath()
            c.fill(liquid, with: .linearGradient(Gradient(colors: [
                Color(red: 0.8, green: 0.48, blue: 1).opacity(layer == 0 ? 0.5 : 0.95),
                Color(red: 0.35, green: 0.08, blue: 0.8)
            ]), startPoint: CGPoint(x: 0, y: level), endPoint: CGPoint(x: 0, y: rect.maxY)))
        }
        // Fresnel rim and a broad curved reflection make the orb read as glass.
        c.stroke(shell, with: .linearGradient(Gradient(colors: [.white.opacity(0.8), .white.opacity(0.08), .white.opacity(0.35)]),
                   startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1.3)
        let shine = CGRect(x: size.width * 0.2, y: size.height * 0.12, width: size.width * 0.4, height: size.height * 0.14)
        c.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.3)))
    }
}

extension Notification.Name {
    static let mirsaLiquidCompletion = Notification.Name("mirsa.ui.liquidCompletion")
}

/// Short, bounded particle lifetime; no timer, sensors or off-screen render loop.
struct MirsaCompletionSparkles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started: Date?
    private static func starPath(center: CGPoint, p: Double) -> Path {
        var star = Path()
        for corner in 0..<8 {
            let a: Double = Double(corner) * Double.pi / 4
            let big: Double = corner % 2 == 0 ? 5.0 : 1.6
            let radius: Double = big * (1.0 - p)
            let pt = CGPoint(x: center.x + CGFloat(cos(a) * radius), y: center.y + CGFloat(sin(a) * radius))
            if corner == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
        }
        star.closeSubpath()
        return star
    }

    private static func drawSparkles(context: inout GraphicsContext, size: CGSize, p: Double) {
        for i in 0..<12 {
            let angle: Double = Double(i) * Double.pi / 6
            let distance: Double = 16.0 + p * 78.0
            let px: Double = Double(size.width) / 2.0 + cos(angle) * distance
            let py: Double = Double(size.height) / 2.0 + sin(angle) * distance + p * p * 24.0
            let star = starPath(center: CGPoint(x: px, y: py), p: p)
            let base: Color = i % 3 == 0 ? Color.white : Color.purple
            context.fill(star, with: .color(base.opacity(1.0 - p)))
        }
    }

    var body: some View {
        Group {
            if let started, !reduceMotion, scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: MirsaUITestHarness.active)) { tick in
                    Canvas { context, size in
                        let age: Double = tick.date.timeIntervalSince(started)
                        let p: Double = MirsaUITestHarness.active ? 0.4 : min(1.0, max(0.0, age / 0.85))
                        Self.drawSparkles(context: &context, size: size, p: p)
                    }
                }
                .frame(width: 220, height: 220)
                .task(id: started) {
                    guard !MirsaUITestHarness.active else { return }
                    try? await Task.sleep(for: .seconds(0.9))
                    if !Task.isCancelled { self.started = nil }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .mirsaLiquidCompletion)) { _ in
            guard !reduceMotion, scenePhase == .active else { return }
            started = Date()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { started = nil } }
    }
}

struct MirsaLiquidProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 8) {
            MirsaLiquidProgress(value: configuration.fractionCompleted)
            configuration.label
            configuration.currentValueLabel
        }
    }
}

#if DEBUG
/// Deterministic real-component coverage without downloads, accounts or installs.
struct MirsaLiquidReviewHost: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Liquid progress").font(.title.bold())
                HStack(spacing: 16) {
                    MirsaLiquidProgress(value: 0, diameter: 92)
                    MirsaLiquidProgress(value: 0.47, diameter: 112)
                    MirsaLiquidProgress(value: 1, diameter: 92)
                }
                MirsaLiquidProgress(value: nil, diameter: 80)
                MirsaLiquidProgress(value: 0.47, reviewReduceMotion: true)
                    .accessibilityIdentifier("liquid.reduce-motion")
                Button("Completion") {
                    NotificationCenter.default.post(name: .mirsaLiquidCompletion, object: nil)
                }.accessibilityIdentifier("liquid.complete")
                MirsaLiquidProgress(value: 0.47, diameter: 80)
                    .environment(\.layoutDirection, .rightToLeft)
            }.padding(24)
        }
        .background(Color(red: 0.05, green: 0.04, blue: 0.1))
        .overlay { MirsaCompletionSparkles() }
        .accessibilityIdentifier("liquid.review")
    }
}
#endif
