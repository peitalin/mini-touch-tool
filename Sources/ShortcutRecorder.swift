import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var chord: KeyChord
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(binding: $chord) }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.recorded = context.coordinator.record
        button.setAccessibilityLabel(label)
        button.chord = chord
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        context.coordinator.binding = $chord
        button.setAccessibilityLabel(label)
        button.chord = chord
    }

    final class Coordinator {
        var binding: Binding<KeyChord>
        init(binding: Binding<KeyChord>) { self.binding = binding }
        func record(_ chord: KeyChord) { binding.wrappedValue = chord }
    }
}

final class RecorderButton: NSButton {
    var recorded: ((KeyChord) -> Void)?
    var chord = KeyChord(keyCode: 48, modifiers: [.command]) {
        didSet { if !isRecording { title = chord.label } }
    }
    private(set) var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        target = self
        action = #selector(beginRecord)
        setAccessibilityLabel("Record keyboard shortcut")
        toolTip = "Click, then press the shortcut. Press Escape to cancel."
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecord() {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            finishRecord()
            return
        }
        guard let cgEvent = event.cgEvent else { return }
        let result = KeyChord(keyCode: event.keyCode, modifiers: modifierKeys(cgEvent.flags))
        finishRecord()
        recorded?(result)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        finishRecord()
        return super.resignFirstResponder()
    }

    private func finishRecord() {
        isRecording = false
        title = chord.label
    }
}
