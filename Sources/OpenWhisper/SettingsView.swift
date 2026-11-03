import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "OpenWhisper Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                SecureField("OpenAI API key", text: $settings.apiKey, prompt: Text("sk-…"))
                Picker("Model", selection: $settings.model) {
                    ForEach(Transcriber.models, id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                Text("Audio goes straight from your Mac to OpenAI. The key is stored in your keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Shortcut") { ShortcutRecorder(shortcut: $settings.shortcut) }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } footer: {
                Text("Press the shortcut to start, press again to transcribe and paste. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(title: "Microphone", granted: micGranted) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                        openPrivacyPane("Privacy_Microphone")
                    }
                }
                PermissionRow(title: "Accessibility (to paste)", granted: axGranted) {
                    Paster.requestAccessibility()
                    openPrivacyPane("Privacy_Accessibility")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onReceive(refresh) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            axGranted = AXIsProcessTrusted()
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let grant: () -> Void

    var body: some View {
        LabeledContent(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: grant)
            }
        }
    }
}

/// Click, then press a key combination to set the shortcut.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggle) {
                Text(isRecording ? "Press keys or tap a modifier…" : shortcut.displayString)
                    .frame(minWidth: 180)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        hint = nil
        AppDelegate.shared?.suspendHotKey()
        var pendingModifier: UInt16?
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // A modifier pressed and released on its own records a modifier-tap shortcut.
                guard let tap = Shortcut.modifierTap(keyCode: event.keyCode),
                      let mask = ModifierTapHotKey.keys[Int(event.keyCode)]?.mask else { return event }
                let isDown = event.modifierFlags.rawValue & mask != 0
                let anyHeld = !event.modifierFlags.intersection([.control, .option, .shift, .command, .function]).isEmpty
                if isDown {
                    // A second modifier going down means it's a combo, not a lone tap.
                    pendingModifier = pendingModifier == nil ? event.keyCode : nil
                } else if pendingModifier == event.keyCode && !anyHeld {
                    shortcut = tap
                    stop()
                } else {
                    pendingModifier = nil
                }
                return event
            }
            pendingModifier = nil
            if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop() // plain Esc cancels
                return nil
            }
            switch Shortcut.from(event: event) {
            case .success(let new):
                shortcut = new
                stop()
            case .failure(let error):
                hint = error.message
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        AppDelegate.shared?.resumeHotKey()
    }
}
