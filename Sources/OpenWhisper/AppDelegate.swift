import AppKit
import AVFoundation
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private enum State { case idle, recording, transcribing }

    private let settings = AppSettings.shared
    private let recorder = Recorder()
    private let overlay = OverlayController()
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var state = State.idle { didSet { updateMenu() } }
    private var hotKey: HotKey?
    private var escapeKey: HotKey?
    private var meterTimer: Timer?
    private var transcription: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        installEditMenu()
        setUpStatusItem()
        settings.onShortcutChange = { [weak self] in self?.registerHotKey() }
        registerHotKey()

        if settings.trimmedAPIKey.isEmpty {
            SettingsWindow.shared.show()
        }
    }

    // MARK: Hotkey

    private func registerHotKey() {
        hotKey = nil
        hotKey = HotKey(settings.shortcut) { [weak self] in self?.toggle() }
        if hotKey == nil { NSLog("OpenWhisper: could not register \(settings.shortcut.displayString)") }
        updateMenu()
    }

    func suspendHotKey() { hotKey = nil }
    func resumeHotKey() { if hotKey == nil { registerHotKey() } }

    // MARK: Dictation flow

    @objc private func toggle() {
        switch state {
        case .idle: start()
        case .recording: finish()
        case .transcribing: break
        }
    }

    private func start() {
        guard !settings.trimmedAPIKey.isEmpty else {
            overlay.flash(.error("Add your OpenAI API key in Settings"), for: 2.5)
            SettingsWindow.shared.show()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { [weak self] in
                    if granted { self?.beginRecording() } else { self?.microphoneDenied() }
                }
            }
        default:
            microphoneDenied()
        }
    }

    private func microphoneDenied() {
        overlay.flash(.error("Microphone access is off"), for: 2.5)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func beginRecording() {
        do {
            try recorder.start()
        } catch {
            overlay.flash(.error(error.localizedDescription), for: 2.5)
            return
        }
        state = .recording
        overlay.show(.recording)
        escapeKey = HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] in self?.cancel() }
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.overlay.model.push(level: self.recorder.level())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func finish() {
        meterTimer?.invalidate()
        meterTimer = nil
        let duration = recorder.stop()
        guard duration >= 0.3 else {
            cancel()
            return
        }
        state = .transcribing
        overlay.set(.transcribing)

        let fileURL = recorder.fileURL
        let apiKey = settings.trimmedAPIKey
        let model = settings.model
        transcription = Task { [weak self] in
            do {
                let raw = try await Transcriber.transcribe(fileURL: fileURL, apiKey: apiKey, model: model)
                try Task.checkCancellation()
                self?.deliver(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch is CancellationError {
                // Cancelled with Esc.
            } catch let error as URLError where error.code == .cancelled {
                // Cancelled with Esc.
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func deliver(_ text: String) {
        reset()
        guard !text.isEmpty else {
            overlay.hide()
            return
        }
        if Paster.paste(text) {
            overlay.set(.done)
            overlay.hide(after: 0.7)
        } else {
            overlay.set(.error("Copied — allow Accessibility to auto-paste"))
            overlay.hide(after: 3)
            Paster.requestAccessibility()
        }
    }

    private func fail(_ message: String) {
        reset()
        overlay.set(.error(message))
        overlay.hide(after: 3.5)
    }

    private func cancel() {
        transcription?.cancel()
        recorder.discard()
        reset()
        overlay.hide()
    }

    private func reset() {
        meterTimer?.invalidate()
        meterTimer = nil
        escapeKey = nil
        transcription = nil
        state = .idle
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Dictation", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenWhisper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateMenu()
    }

    private func updateMenu() {
        guard let statusItem else { return }
        let symbol: String
        switch state {
        case .idle:
            symbol = "waveform"
            toggleItem.title = "Start Dictation  (\(settings.shortcut.displayString))"
            toggleItem.isEnabled = true
        case .recording:
            symbol = "waveform.badge.mic"
            toggleItem.title = "Stop & Transcribe  (\(settings.shortcut.displayString))"
            toggleItem.isEnabled = true
        case .transcribing:
            symbol = "ellipsis"
            toggleItem.title = "Transcribing…"
            toggleItem.isEnabled = false
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "OpenWhisper")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    /// Accessory apps have no visible menu bar, but text fields still need ⌘C/⌘V/⌘A to work.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
