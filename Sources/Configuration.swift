import AppKit

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case shift, fn, control, option, command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift: return "⇧ Shift"
        case .fn: return "fn"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .fn: return .maskSecondaryFn
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }
}

struct KeyChord: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: Set<ModifierKey>

    var label: String {
        modifierLabel(modifiers) + keyLabel(keyCode)
    }
}

enum ApplicationScope: Codable, Equatable {
    case allApps
    case application(bundleIdentifier: String, name: String)

    var label: String {
        switch self {
        case .allApps: return "All Apps"
        case .application(_, let name): return name
        }
    }

    func matches(_ bundleIdentifier: String) -> Bool {
        switch self {
        case .allApps: return true
        case .application(let identifier, _): return identifier == bundleIdentifier
        }
    }
}

enum TrackpadGesture: String, Codable, CaseIterable, Identifiable {
    case threeFingerClick
    case fourFingerSwipeDown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .threeFingerClick: return "3-Finger Click"
        case .fourFingerSwipeDown: return "4-Finger Swipe Down"
        }
    }
}

enum ShortcutTrigger: Codable, Equatable {
    case keyboard(KeyChord)
    case trackpad(TrackpadGesture)

    var label: String {
        switch self {
        case .keyboard(let chord): return chord.label
        case .trackpad(let gesture): return gesture.label
        }
    }
}

enum ShortcutAction: Codable, Equatable {
    case sendShortcut(KeyChord)
    case minimizeWindow

    var label: String {
        switch self {
        case .sendShortcut(let chord): return chord.label
        case .minimizeWindow: return "Minimize window under pointer"
        }
    }
}

struct ShortcutRule: Identifiable, Codable, Equatable {
    var id: UUID
    var enabled: Bool
    var scope: ApplicationScope
    var trigger: ShortcutTrigger
    var action: ShortcutAction

    static var newRule: ShortcutRule {
        ShortcutRule(id: UUID(), enabled: true, scope: .allApps,
                     trigger: .keyboard(KeyChord(keyCode: 48, modifiers: [.control, .option])),
                     action: .sendShortcut(KeyChord(keyCode: 48, modifiers: [.control, .shift])))
    }
}

struct WindowPreferences: Codable, Equatable {
    var moveModifiers: Set<ModifierKey>
    var resizeModifiers: Set<ModifierKey>
    var threshold: Int
    var raiseWindow: Bool
}

struct AppConfiguration: Codable, Equatable {
    var shortcuts: [ShortcutRule]
    var windows: WindowPreferences

    static var defaults: AppConfiguration {
        AppConfiguration(shortcuts: [
            ShortcutRule(id: UUID(), enabled: true, scope: .allApps,
                         trigger: .trackpad(.threeFingerClick),
                         action: .sendShortcut(KeyChord(keyCode: 13, modifiers: [.command]))),
            ShortcutRule(id: UUID(), enabled: true,
                         scope: .application(bundleIdentifier: "com.googlecode.iterm2", name: "iTerm"),
                         trigger: .keyboard(KeyChord(keyCode: 48, modifiers: [.control])),
                         action: .sendShortcut(KeyChord(keyCode: 30, modifiers: [.shift, .command]))),
            ShortcutRule(id: UUID(), enabled: true,
                         scope: .application(bundleIdentifier: "com.googlecode.iterm2", name: "iTerm"),
                         trigger: .keyboard(KeyChord(keyCode: 48, modifiers: [.command])),
                         action: .sendShortcut(KeyChord(keyCode: 33, modifiers: [.shift, .command]))),
            ShortcutRule(id: UUID(), enabled: true, scope: .allApps,
                         trigger: .trackpad(.fourFingerSwipeDown), action: .minimizeWindow),
            ShortcutRule(id: UUID(), enabled: true, scope: .allApps,
                         trigger: .keyboard(KeyChord(keyCode: 48, modifiers: [.command])),
                         action: .sendShortcut(KeyChord(keyCode: 48, modifiers: [.control, .shift])))
        ], windows: WindowPreferences(moveModifiers: [.fn], resizeModifiers: [.fn, .shift],
                                       threshold: 2, raiseWindow: true))
    }

    func matchingRule(_ trigger: ShortcutTrigger, application: String) -> ShortcutRule? {
        var global: ShortcutRule?
        for rule in shortcuts where rule.enabled && rule.trigger == trigger {
            switch rule.scope {
            case .application:
                if rule.scope.matches(application) { return rule }
            case .allApps:
                global = rule
            }
        }
        return global
    }

    func validate() throws {
        guard !windows.moveModifiers.isEmpty, !windows.resizeModifiers.isEmpty else {
            throw ConfigurationError("Select at least one modifier for each window control.")
        }
        guard windows.moveModifiers != windows.resizeModifiers else {
            throw ConfigurationError("Move and resize need different modifiers.")
        }
        guard (0...100).contains(windows.threshold) else {
            throw ConfigurationError("The movement threshold must be between 0 and 100 pixels.")
        }
        guard Set(shortcuts.map(\.id)).count == shortcuts.count else {
            throw ConfigurationError("Shortcut identifiers must be unique.")
        }
        for (index, rule) in shortcuts.enumerated() {
            if case .application(let identifier, let name) = rule.scope {
                guard !identifier.trimmingCharacters(in: .whitespaces).isEmpty,
                      !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw ConfigurationError("Choose an application for shortcut \(index + 1).")
                }
            }
            if case .keyboard(let chord) = rule.trigger {
                try validateChord(chord)
                guard !chord.modifiers.isEmpty else {
                    throw ConfigurationError("Add a modifier to the trigger for shortcut \(index + 1).")
                }
            }
            if case .sendShortcut(let chord) = rule.action { try validateChord(chord) }
            for other in shortcuts.prefix(index) where other.enabled && rule.enabled {
                guard other.scope != rule.scope || other.trigger != rule.trigger else {
                    throw ConfigurationError("Two enabled shortcuts use \(rule.trigger.label) in \(rule.scope.label).")
                }
            }
        }
    }
}

struct ConfigurationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func loadConfiguration() -> AppConfiguration {
    guard let data = UserDefaults.standard.data(forKey: "configuration"),
          let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data),
          (try? configuration.validate()) != nil else {
        return .defaults
    }
    return configuration
}

func modifierFlags(_ keys: Set<ModifierKey>) -> CGEventFlags {
    var flags: CGEventFlags = []
    for key in keys { flags.insert(key.flag) }
    return flags
}

func modifierKeys(_ flags: CGEventFlags) -> Set<ModifierKey> {
    var keys: Set<ModifierKey> = []
    for key in ModifierKey.allCases where flags.contains(key.flag) { keys.insert(key) }
    return keys
}

func modifierLabel(_ keys: Set<ModifierKey>) -> String {
    var label = ""
    for key in [ModifierKey.control, .option, .shift, .command, .fn] where keys.contains(key) {
        switch key {
        case .control: label += "⌃"
        case .option: label += "⌥"
        case .shift: label += "⇧"
        case .command: label += "⌘"
        case .fn: label += "fn "
        }
    }
    return label
}

func keyLabel(_ code: UInt16) -> String {
    let labels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 65: ".", 67: "*",
        69: "+", 71: "Clear", 75: "/", 76: "Enter", 78: "−", 81: "=", 82: "0", 83: "1",
        84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    return labels[code] ?? "Key \(code)"
}

private func validateChord(_ chord: KeyChord) throws {
    guard chord.keyCode <= 127, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(chord.keyCode) else {
        throw ConfigurationError("Record a key with optional modifiers.")
    }
}
