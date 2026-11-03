import Foundation
import ServiceManagement

/// User preferences. The API key lives in the keychain; everything else in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var apiKey: String {
        didSet { Keychain.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    @Published var shortcut: Shortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: "shortcut") }
            onShortcutChange?()
        }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: "model") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("OpenWhisper: launch-at-login change failed: \(error)")
            }
        }
    }

    var onShortcutChange: (() -> Void)?

    var trimmedAPIKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private init() {
        apiKey = Keychain.read() ?? ""
        if let data = defaults.data(forKey: "shortcut"), let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
        model = defaults.string(forKey: "model") ?? Transcriber.models[0]

        // Turn on launch-at-login the first time the app runs.
        if !defaults.bool(forKey: "didConfigureLoginItem") {
            defaults.set(true, forKey: "didConfigureLoginItem")
            try? SMAppService.mainApp.register()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
