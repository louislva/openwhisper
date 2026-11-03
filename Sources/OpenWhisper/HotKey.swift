import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a virtual key code plus modifier flags.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt          // NSEvent.ModifierFlags raw value
    var keyLabel: String         // e.g. "Space", "D", "F5"

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "Space"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyLabel
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Builds a shortcut from a key-down event, or explains why it can't be used.
    static func from(event: NSEvent) -> Result<Shortcut, ShortcutError> {
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let label = keyLabel(for: event)
        let isFunctionKey = functionKeyCodes.contains(Int(event.keyCode))
        if mods.isEmpty && !isFunctionKey {
            return .failure(.needsModifier)
        }
        // macOS 15+ refuses global hotkeys that only use ⌥ and/or ⇧.
        if !mods.isEmpty && mods.isSubset(of: [.option, .shift]) {
            return .failure(.optionShiftOnly)
        }
        return .success(Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue, keyLabel: label))
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static func keyLabel(for event: NSEvent) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let name = named[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

enum ShortcutError: Error {
    case needsModifier, optionShiftOnly

    var message: String {
        switch self {
        case .needsModifier: return "Add ⌃ or ⌘ to the shortcut"
        case .optionShiftOnly: return "macOS blocks ⌥/⇧-only shortcuts — add ⌃ or ⌘"
        }
    }
}

/// A system-wide hotkey registered through Carbon. Needs no special permissions.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F57_4852), id: id) // 'OWHR'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    convenience init?(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        self.init(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, handler: handler)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKey.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
