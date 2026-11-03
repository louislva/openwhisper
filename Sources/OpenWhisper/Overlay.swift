import AppKit
import SwiftUI

enum OverlayPhase: Equatable {
    case recording
    case transcribing
    case done
    case error(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    static let barCount = 18

    @Published var visible = false
    @Published var phase: OverlayPhase = .recording
    @Published var levels = [CGFloat](repeating: 0, count: barCount)

    func push(level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
    }

    func resetLevels() {
        levels = [CGFloat](repeating: 0, count: Self.barCount)
    }
}

/// The floating pill at the bottom-center of the screen. Never takes focus or mouse input.
@MainActor
final class OverlayController {
    let model = OverlayModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private static let size = NSSize(width: 360, height: 64)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    func show(_ phase: OverlayPhase) {
        hideWork?.cancel()
        model.phase = phase
        if !model.visible {
            model.resetLevels()
            position()
            panel.orderFrontRegardless()
            model.visible = true
        }
    }

    func set(_ phase: OverlayPhase) {
        model.phase = phase
    }

    /// Shows a phase briefly, then hides.
    func flash(_ phase: OverlayPhase, for seconds: TimeInterval) {
        show(phase)
        hide(after: seconds)
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.visible = false
            let orderOut = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            self.hideWork = orderOut
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: orderOut)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Bottom-center of the screen with the mouse, just above the Dock.
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 6)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

// MARK: - Views

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.visible {
                Pill(model: model)
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.visible)
    }
}

private struct Pill: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .recording:
                RecordingDot()
                LevelBars(levels: model.levels)
            case .transcribing:
                ThinkingWave()
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.9, blue: 0.55))
                    .transition(.scale.combined(with: .opacity))
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .frame(minWidth: 34)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.phase)
    }
}

private struct RecordingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color(red: 1, green: 0.27, blue: 0.27))
            .frame(width: 7, height: 7)
            .opacity(pulse ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// A scrolling level history: newest sample on the right.
private struct LevelBars: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.55 + 0.45 * Double(i) / Double(levels.count)))
                    .frame(width: 2.5, height: 3 + levels[i] * 17)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.06), value: levels)
    }
}

/// A travelling sine wave while waiting on OpenAI.
private struct ThinkingWave: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<OverlayModel.barCount, id: \.self) { i in
                    let phase = sin(t * 5 - Double(i) * 0.45)
                    Capsule()
                        .fill(Color.white.opacity(0.35 + 0.35 * (phase + 1) / 2))
                        .frame(width: 2.5, height: 3 + 7 * (phase + 1) / 2)
                }
            }
            .frame(height: 20)
        }
    }
}
