import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class SettingsModel: ObservableObject {
    @Published var draft: AppConfiguration
    @Published var selectedRuleID: UUID?
    @Published var editor: RuleEditorModel?
    @Published var status = ""
    @Published var detail = ""
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var launchAtLogin = false
    @Published var message: String?
    private unowned let controller: AppController

    init(controller: AppController, configuration: AppConfiguration) {
        self.controller = controller
        draft = configuration
        selectedRuleID = configuration.shortcuts.first?.id
    }

    var hasChanges: Bool { draft != controller.configuration }

    func apply() {
        do {
            try draft.validate()
            let data = try JSONEncoder().encode(draft)
            UserDefaults.standard.set(data, forKey: "configuration")
            controller.applyConfiguration(draft)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func discardChanges() {
        draft = controller.configuration
        message = nil
    }

    func restoreDefaults() {
        draft = .defaults
        selectedRuleID = draft.shortcuts.first?.id
        message = nil
    }

    func addRule() { editor = RuleEditorModel(rule: .newRule, owner: self) }

    func editRule() {
        guard let rule = draft.shortcuts.first(where: isSelected) else { return }
        editor = RuleEditorModel(rule: rule, owner: self)
    }

    func removeRule() {
        draft.shortcuts.removeAll(where: isSelected)
        selectedRuleID = draft.shortcuts.first?.id
    }

    func updateRule(_ rule: ShortcutRule) {
        if let index = ruleIndex(rule.id, in: draft.shortcuts) {
            draft.shortcuts[index] = rule
        } else {
            draft.shortcuts.append(rule)
        }
        selectedRuleID = rule.id
        editor = nil
    }

    func cancelEdit() { editor = nil }
    func togglePause() { controller.togglePause() }
    func toggleLogin() { controller.toggleLogin() }
    func requestAccessibility() { controller.requestAccessibility() }
    func requestInputMonitoring() { controller.requestInputMonitoring() }
    func restartInput() { controller.restartInput() }
    func openTrackpadSettings() { controller.openTrackpadSettings() }
    func quit() { NSApplication.shared.terminate(nil) }

    private func isSelected(_ rule: ShortcutRule) -> Bool { rule.id == selectedRuleID }
}

enum TriggerChoice: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard Shortcut"
    case threeFingerClick = "3-Finger Click"
    case fourFingerSwipeDown = "4-Finger Swipe Down"
    var id: String { rawValue }
}

enum ActionChoice: String, CaseIterable, Identifiable {
    case shortcut = "Send Keyboard Shortcut"
    case minimize = "Minimize Window Under Pointer"
    var id: String { rawValue }
}

final class RuleEditorModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var rule: ShortcutRule
    @Published var error: String?
    private unowned let owner: SettingsModel

    init(rule: ShortcutRule, owner: SettingsModel) {
        self.rule = rule
        self.owner = owner
    }

    var triggerChoice: Binding<TriggerChoice> { Binding(get: getTriggerChoice, set: setTriggerChoice) }
    var actionChoice: Binding<ActionChoice> { Binding(get: getActionChoice, set: setActionChoice) }
    var triggerChord: Binding<KeyChord> { Binding(get: getTriggerChord, set: setTriggerChord) }
    var actionChord: Binding<KeyChord> { Binding(get: getActionChord, set: setActionChord) }

    func getTriggerChoice() -> TriggerChoice {
        switch rule.trigger {
        case .keyboard: return .keyboard
        case .trackpad(.threeFingerClick): return .threeFingerClick
        case .trackpad(.fourFingerSwipeDown): return .fourFingerSwipeDown
        }
    }

    func setTriggerChoice(_ choice: TriggerChoice) {
        switch choice {
        case .keyboard: rule.trigger = .keyboard(KeyChord(keyCode: 48, modifiers: [.command]))
        case .threeFingerClick: rule.trigger = .trackpad(.threeFingerClick)
        case .fourFingerSwipeDown: rule.trigger = .trackpad(.fourFingerSwipeDown)
        }
    }

    func getActionChoice() -> ActionChoice {
        switch rule.action {
        case .sendShortcut: return .shortcut
        case .minimizeWindow: return .minimize
        }
    }

    func setActionChoice(_ choice: ActionChoice) {
        switch choice {
        case .shortcut: rule.action = .sendShortcut(KeyChord(keyCode: 13, modifiers: [.command]))
        case .minimize: rule.action = .minimizeWindow
        }
    }

    func getTriggerChord() -> KeyChord {
        if case .keyboard(let chord) = rule.trigger { return chord }
        return KeyChord(keyCode: 48, modifiers: [.command])
    }

    func setTriggerChord(_ chord: KeyChord) { rule.trigger = .keyboard(chord) }

    func getActionChord() -> KeyChord {
        if case .sendShortcut(let chord) = rule.action { return chord }
        return KeyChord(keyCode: 13, modifiers: [.command])
    }

    func setActionChord(_ chord: KeyChord) { rule.action = .sendShortcut(chord) }
    func useAllApps() { rule.scope = .allApps }
    func useITerm() { rule.scope = .application(bundleIdentifier: "com.googlecode.iterm2", name: "iTerm") }

    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        rule.scope = .application(bundleIdentifier: identifier, name: name)
    }

    func save() {
        var candidate = owner.draft
        if let index = ruleIndex(rule.id, in: candidate.shortcuts) { candidate.shortcuts.remove(at: index) }
        candidate.shortcuts.append(rule)
        do {
            try candidate.validate()
            owner.updateRule(rule)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func cancel() { owner.cancelEdit() }
}

private func ruleIndex(_ identifier: UUID, in rules: [ShortcutRule]) -> Int? {
    for index in rules.indices where rules[index].id == identifier { return index }
    return nil
}
