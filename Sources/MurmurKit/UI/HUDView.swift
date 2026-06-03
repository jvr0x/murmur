import AppKit
import SwiftUI

/// Observable state driving the HUD's SwiftUI animation.
@MainActor
final class HUDModel: ObservableObject {
    /// The current pipeline state the HUD reflects.
    @Published var state: DictationState = .recording
}

/// The floating status HUD: the app logo, an animated Solana-gradient waveform that
/// reflects the pipeline state, and a status label.
struct HUDView: View {
    /// The state model, observed for live updates.
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 14) {
            if let logo = Self.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
            }
            VStack(spacing: 6) {
                WaveformView(state: model.state)
                    .frame(width: 152, height: 38)
                Text(model.state.hudLabel ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .opacity(0.85)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The app icon, loaded once from the bundle for use as the HUD logo.
    static let logo: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }()
}

/// An animated waveform whose motion reflects the dictation state, drawn with the
/// Solana purple→green gradient.
struct WaveformView: View {
    /// The state whose animation to render.
    let state: DictationState

    /// Solana gradient endpoints.
    private static let purple = Color(red: 0.600, green: 0.271, blue: 1.0)
    /// Solana gradient endpoint.
    private static let green = Color(red: 0.078, green: 0.945, blue: 0.584)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(&context, size: size, state: state, t: t)
            }
        }
    }

    /// Draws the state-specific waveform into the graphics context.
    /// - Parameters:
    ///   - context: The canvas graphics context.
    ///   - size: The canvas size.
    ///   - state: The dictation state selecting the visual style.
    ///   - t: The current time, in seconds, driving the animation.
    private static func draw(_ context: inout GraphicsContext, size: CGSize,
                             state: DictationState, t: Double) {
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [purple, green]),
            startPoint: .zero,
            endPoint: CGPoint(x: size.width, y: 0)
        )
        let mid = size.height / 2

        switch state {
        case .recording:
            // Lively reactive bars, each with its own phase and speed.
            let n = 11
            let gap: CGFloat = 5
            let barW = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            for i in 0..<n {
                let phase = Double(i) * 0.8
                let speed = 3.2 + Double(i % 3) * 0.7
                let level = 0.5 + 0.5 * sin(t * speed + phase)
                let h = barW + CGFloat(level) * (size.height - barW)
                let rect = CGRect(x: CGFloat(i) * (barW + gap),
                                  y: mid - h / 2, width: barW, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: shading)
            }

        case .transcribing:
            // A sine that flows left→right (processing).
            context.stroke(
                Self.sine(size: size, amplitude: size.height * 0.34, cycles: 2.0, phase: -t * 3.2),
                with: shading,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

        case .cleaning:
            // A slower sine whose amplitude gently pulses (a soft "polish").
            let pulse = 0.55 + 0.45 * sin(t * 2.0)
            context.stroke(
                Self.sine(size: size, amplitude: size.height * 0.30 * CGFloat(pulse),
                          cycles: 1.5, phase: -t * 1.6),
                with: shading,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

        case .inserting:
            // Settled flat line.
            var path = Path()
            path.move(to: CGPoint(x: 3, y: mid))
            path.addLine(to: CGPoint(x: size.width - 3, y: mid))
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: 5, lineCap: .round))

        case .idle:
            break
        }
    }

    /// Builds a sine-wave path across the full width.
    /// - Parameters:
    ///   - size: The drawing area.
    ///   - amplitude: Peak vertical deviation from the midline.
    ///   - cycles: Number of full waves across the width.
    ///   - phase: Phase offset, in radians (animate to make the wave travel).
    /// - Returns: The sine path.
    private static func sine(size: CGSize, amplitude: CGFloat,
                             cycles: Double, phase: Double) -> Path {
        var path = Path()
        let mid = size.height / 2
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= size.width {
            let frac = Double(x / size.width)
            let y = mid + amplitude * CGFloat(sin(frac * .pi * 2 * cycles + phase))
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            x += step
        }
        return path
    }
}
