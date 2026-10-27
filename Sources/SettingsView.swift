import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView {
                shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
                windowControls.tabItem { Label("Window Controls", systemImage: "macwindow") }
                setup.tabItem { Label("Setup", systemImage: "gearshape") }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            Divider()
            footer
        }
        .frame(minWidth: 790, idealWidth: 850, minHeight: 570, idealHeight: 620)
        .sheet(item: $model.editor, content: editorView)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text("Mini Touch Tool").font(.system(size: 22, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(model.isRunning ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(model.isPaused ? "Resume" : "Pause", action: model.togglePause)
        }
        .padding(24)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your shortcuts").font(.headline)
                Spacer()
                Text("Application rules take priority over All Apps.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 18)

            Table(model.draft.shortcuts, selection: $model.selectedRuleID) {
                TableColumn("On") { rule in
                    Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(rule.enabled ? Color.accentColor : Color.secondary)
                        .accessibilityLabel(rule.enabled ? "Enabled" : "Disabled")
                }.width(32)
                TableColumn("Application") { rule in Text(rule.scope.label) }.width(min: 100, ideal: 130)
                TableColumn("Trigger") { rule in
                    Label(rule.trigger.label, systemImage: triggerIcon(rule.trigger))
                        .font(.system(size: 13, weight: .medium))
                }.width(min: 150, ideal: 200)
                TableColumn("Action") { rule in Text(rule.action.label) }
            }
            .contextMenu(forSelectionType: UUID.self, menu: selectionMenu, primaryAction: editSelection)

            HStack(spacing: 8) {
                Button("Add Shortcut", systemImage: "plus", action: model.addRule)
                Button("Edit…", action: model.editRule).disabled(model.selectedRuleID == nil)
                Button("Remove", action: model.removeRule).disabled(model.selectedRuleID == nil)
                Spacer()
            }
            Text("A click means a physical trackpad press. Changes take effect after you select Apply Changes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var windowControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 32) {
                    ModifierSelector(title: "Move windows", symbol: "arrow.up.and.down.and.arrow.left.and.right",
                                     keys: $model.draft.windows.moveModifiers)
                    Divider()
                    ModifierSelector(title: "Resize windows", symbol: "arrow.up.left.and.arrow.down.right",
                                     keys: $model.draft.windows.resizeModifiers)
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("Hold the selected keys and move the pointer over a window. No mouse click is needed.")
                    .foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 12) {
                    Text("Movement threshold")
                    Stepper(value: $model.draft.windows.threshold, in: 0...100) {
                        Text("\(model.draft.windows.threshold) pixels").monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                    .fixedSize()
                }
                Toggle("Bring the window to front when a move or resize starts", isOn: $model.draft.windows.raiseWindow)
                Text("Resize uses the corner nearest the pointer. Apps can set their own minimum window size.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Launch at Login").font(.headline)
                            Text("Start Mini Touch Tool when you sign in to your Mac.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Launch at Login", isOn: loginBinding).labelsHidden()
                    }
                    .padding(10)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Permissions").font(.headline)
                    Text("Allow Mini Touch Tool in both privacy panels. macOS needs these permissions to control windows and shortcuts.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Accessibility…", action: model.requestAccessibility)
                        Button("Input Monitoring…", action: model.requestInputMonitoring)
                        Button("Restart Input", action: model.restartInput)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trackpad and Fn key").font(.headline)
                    Text("Quit BetterTouchTool before you enable this app. Disable four-finger App Exposé if it uses the same gesture.")
                        .foregroundStyle(.secondary)
                    Text("If Fn opens another feature, set “Press Fn/🌐 key to” to “Do Nothing” in Keyboard settings.")
                        .foregroundStyle(.secondary)
                    Button("Trackpad Settings…", action: model.openTrackpadSettings)
                }
                Text("\(model.detail)\nGestures use Apple's private interface. A macOS update may require a repair. Secure Input can block keyboard shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Quit", action: model.quit)
                Button("Restore Defaults", action: model.restoreDefaults)
                Spacer()
                Text(model.hasChanges ? "Unsaved changes" : "Settings saved").font(.caption).foregroundStyle(.secondary)
                Button("Discard", action: model.discardChanges).disabled(!model.hasChanges)
                Button("Apply Changes", action: model.apply)
                    .buttonStyle(.borderedProminent).disabled(!model.hasChanges)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var loginBinding: Binding<Bool> { Binding(get: getLogin, set: setLogin) }
    private func getLogin() -> Bool { model.launchAtLogin }
    private func setLogin(_ value: Bool) { model.toggleLogin() }
    private func editorView(_ editor: RuleEditorModel) -> RuleEditorView { RuleEditorView(model: editor) }
    private func editSelection(_ identifiers: Set<UUID>) { model.selectedRuleID = identifiers.first; model.editRule() }
    private func selectionMenu(_ identifiers: Set<UUID>) -> some View { Button("Edit…", action: model.editRule) }
}

private struct ModifierSelector: View {
    let title: String
    let symbol: String
    @Binding var keys: Set<ModifierKey>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline)
            Text(modifierLabel(keys).isEmpty ? "Select modifiers" : modifierLabel(keys))
                .font(.system(size: 23, weight: .medium, design: .monospaced))
                .frame(height: 32)
            HStack(spacing: 14) {
                ForEach(ModifierKey.allCases) { modifier in
                    Toggle(modifierLabel([modifier]), isOn: binding(for: modifier))
                        .toggleStyle(.checkbox).help(modifier.title).accessibilityLabel(modifier.title)
                }
            }
            Text("Shift · Fn · Control · Option · Command").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for key: ModifierKey) -> Binding<Bool> {
        Binding(get: { keys.contains(key) }, set: { enabled in
            if enabled { keys.insert(key) } else { keys.remove(key) }
        })
    }
}

private struct RuleEditorView: View {
    @ObservedObject var model: RuleEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Edit Shortcut").font(.title2).fontWeight(.semibold)
            Form {
                Toggle("Enabled", isOn: $model.rule.enabled)
                LabeledContent("Application") {
                    Menu(model.rule.scope.label) {
                        Button("All Apps", action: model.useAllApps)
                        Button("iTerm", action: model.useITerm)
                        Divider()
                        Button("Choose Application…", action: model.chooseApplication)
                    }.frame(width: 255)
                }
                Picker("Trigger", selection: model.triggerChoice) {
                    ForEach(TriggerChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }
                if case .keyboard = model.rule.trigger {
                    LabeledContent("Press these keys") {
                        ShortcutRecorder(chord: model.triggerChord, label: "Record trigger shortcut").frame(width: 255, height: 30)
                    }
                }
                Picker("Action", selection: model.actionChoice) {
                    ForEach(ActionChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }
                if case .sendShortcut = model.rule.action {
                    LabeledContent("Send these keys") {
                        ShortcutRecorder(chord: model.actionChord, label: "Record action shortcut").frame(width: 255, height: 30)
                    }
                }
            }
            .formStyle(.columns)
            Text("Click a key field, then press the shortcut. Press Escape to cancel the key record.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel", action: model.cancel)
                Button("Save Shortcut", action: model.save).buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 535)
    }
}

private func triggerIcon(_ trigger: ShortcutTrigger) -> String {
    switch trigger {
    case .keyboard: return "keyboard"
    case .trackpad: return "hand.draw"
    }
}
