import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: either a key plus modifier flags, or a lone tap of one modifier key
/// (e.g. Right ⌥), in which case `keyCode` is that modifier's key code and `modifiers` is 0.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt          // NSEvent.ModifierFlags raw value
    var keyLabel: String         // e.g. "Space", "D", "F5", "Right ⌥"

    static let `default` = Shortcut(keyCode: UInt32(kVK_RightOption), modifiers: 0, keyLabel: "Right ⌥")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var isModifierTap: Bool { ModifierTapHotKey.keys[Int(keyCode)] != nil }

    var displayString: String {
        if isModifierTap { return keyLabel }
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

    /// A shortcut for tapping a single modifier key, if `keyCode` is one.
    static func modifierTap(keyCode: UInt16) -> Shortcut? {
        guard let key = ModifierTapHotKey.keys[Int(keyCode)] else { return nil }
        return Shortcut(keyCode: UInt32(keyCode), modifiers: 0, keyLabel: key.label)
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

/// Fires when a single modifier key (e.g. Right ⌥) is tapped on its own: pressed and released
/// quickly with no other key, modifier or click in between. Holding it to type ⌥-characters
/// or ⌥-click doesn't trigger. Uses global event monitors, which need Accessibility access.
final class ModifierTapHotKey {
    /// Modifier key codes, with the device-specific flag bit that tells left from right.
    static let keys: [Int: (label: String, mask: UInt)] = [
        kVK_RightOption: ("Right ⌥", 0x40), kVK_Option: ("Left ⌥", 0x20),
        kVK_RightCommand: ("Right ⌘", 0x10), kVK_Command: ("Left ⌘", 0x08),
        kVK_RightControl: ("Right ⌃", 0x2000), kVK_Control: ("Left ⌃", 0x01),
        kVK_RightShift: ("Right ⇧", 0x04), kVK_Shift: ("Left ⇧", 0x02),
        kVK_Function: ("fn", NSEvent.ModifierFlags.function.rawValue),
    ]
    private static let maxTapDuration: TimeInterval = 0.5

    private let keyCode: UInt16
    private let mask: UInt
    private let handler: () -> Void
    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var interrupted = false

    init?(keyCode: UInt32, handler: @escaping () -> Void) {
        guard let key = Self.keys[Int(keyCode)] else { return nil }
        self.keyCode = UInt16(keyCode)
        self.mask = key.mask
        self.handler = handler
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            if pressedAt != nil { interrupted = true }
            return
        }
        guard event.keyCode == keyCode else {
            if pressedAt != nil { interrupted = true }
            return
        }
        let isDown = event.modifierFlags.rawValue & mask != 0
        if isDown {
            pressedAt = Date()
            // Other modifiers already held means it's part of a combo, not a lone tap.
            let others = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
                .subtracting(Self.familyFlag(for: keyCode))
            interrupted = !others.isEmpty
        } else if let pressedAt {
            if !interrupted && Date().timeIntervalSince(pressedAt) < Self.maxTapDuration {
                handler()
            }
            self.pressedAt = nil
        }
    }

    private static func familyFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch Int(keyCode) {
        case kVK_RightOption, kVK_Option: return .option
        case kVK_RightCommand, kVK_Command: return .command
        case kVK_RightControl, kVK_Control: return .control
        case kVK_RightShift, kVK_Shift: return .shift
        default: return .function
        }
    }
}
