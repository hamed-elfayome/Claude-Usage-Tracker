//
//  ShortcutManager.swift
//  Claude Usage
//
//  Global keyboard shortcut manager using Carbon RegisterEventHotKey
//  No Accessibility permission required.
//

import Cocoa
import Carbon

// MARK: - Models

enum ShortcutAction: String, CaseIterable {
    case togglePopover
    case refresh
    case openSettings
    case nextProfile
}

struct KeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
    }

    var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    /// Convert NSEvent modifier flags to Carbon modifier flags
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        let flags = nsModifierFlags
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    var carbonKeyCode: UInt32 {
        UInt32(keyCode)
    }

    var displayString: String {
        var parts: [String] = []
        let flags = nsModifierFlags
        if flags.contains(.control) { parts.append("\u{2303}") }
        if flags.contains(.option) { parts.append("\u{2325}") }
        if flags.contains(.shift) { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        parts.append(KeyCombo.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "\u{21A9}" // Return
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "\u{21E5}" // Tab
        case 49: return "\u{2423}" // Space
        case 50: return "`"
        case 51: return "\u{232B}" // Delete
        case 53: return "\u{238B}" // Escape
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "\u{2190}" // Left
        case 124: return "\u{2192}" // Right
        case 125: return "\u{2193}" // Down
        case 126: return "\u{2191}" // Up
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - ShortcutManager

class ShortcutManager {
    static let shared = ShortcutManager()

    /// FourCharCode signature for our hotkey events
    private static let hotKeySignature: FourCharCode = {
        var result: FourCharCode = 0
        for char in "CUHk".utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }()

    private var registeredHotKeys: [UInt32: (ref: EventHotKeyRef, action: ShortcutAction)] = [:]
    private var nextHotKeyID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private(set) var shortcuts: [ShortcutAction: KeyCombo] = [:]

    var onTogglePopover: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onNextProfile: (() -> Void)?

    private init() {
        loadShortcuts()
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        let store = SharedDataStore.shared
        for action in ShortcutAction.allCases {
            if let combo = store.loadShortcut(for: action) {
                shortcuts[action] = combo
            }
        }
    }

    func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) {
        if let combo = combo {
            shortcuts[action] = combo
        } else {
            shortcuts.removeValue(forKey: action)
        }
        SharedDataStore.shared.saveShortcut(combo, for: action)

        // Re-register all hotkeys
        stopListening()
        startListening()
    }

    // MARK: - Carbon Hotkey Registration

    func startListening() {
        guard eventHandler == nil else { return }
        guard !shortcuts.isEmpty else {
            LoggingService.shared.log("ShortcutManager: No shortcuts configured, skipping")
            return
        }

        // Install the Carbon event handler
        installEventHandler()

        // Register each shortcut
        for (action, combo) in shortcuts {
            registerHotKey(combo, for: action)
        }

        LoggingService.shared.log("ShortcutManager: Started listening for \(shortcuts.count) shortcut(s): \(shortcuts.map { "\($0.key.rawValue)=\($0.value.displayString)" }.joined(separator: ", "))")
    }

    func stopListening() {
        // Unregister all hotkeys
        for (_, entry) in registeredHotKeys {
            UnregisterEventHotKey(entry.ref)
        }
        registeredHotKeys.removeAll()
        nextHotKeyID = 1

        // Remove event handler
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
        ]

        // Store a pointer to self for the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonEvent(event)
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandler
        )
    }

    private func registerHotKey(_ combo: KeyCombo, for action: ShortcutAction) {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: nextHotKeyID)

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.carbonKeyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            registeredHotKeys[nextHotKeyID] = (ref: ref, action: action)
            LoggingService.shared.log("ShortcutManager: Registered hotkey \(combo.displayString) for \(action.rawValue) (id=\(nextHotKeyID))")
            nextHotKeyID += 1
        } else {
            LoggingService.shared.log("ShortcutManager: Failed to register hotkey \(combo.displayString), status=\(status)")
        }
    }

    private func handleCarbonEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        guard hotKeyID.signature == Self.hotKeySignature,
              let entry = registeredHotKeys[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [weak self] in
            self?.executeAction(entry.action)
        }

        return noErr
    }

    private func executeAction(_ action: ShortcutAction) {
        LoggingService.shared.log("ShortcutManager: Executing \(action.rawValue)")
        switch action {
        case .togglePopover:
            onTogglePopover?()
        case .refresh:
            onRefresh?()
        case .openSettings:
            onOpenSettings?()
        case .nextProfile:
            onNextProfile?()
        }
    }
}
