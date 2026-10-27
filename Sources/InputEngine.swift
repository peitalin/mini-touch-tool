import AppKit
import ApplicationServices

private let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
private let generatedEventMarker: Int64 = 0x4C6974746C65

private enum PressedKey {
    case replaced(KeyChord)
    case consumed
}

private enum DragState {
    case idle
    case armed(WindowDrag)
    case active(WindowDrag)
}

private enum SwipeState {
    case idle
    case tracking(origin: CGPoint, timestamp: Double)
    case consumed
}

private struct ContactState {
    let count: Int
    let timestamp: Double
    let swipe: SwipeState
}

enum InputStartError: Error {
    case eventTapUnavailable
}

final class InputEngine {
    private let configuration: AppConfiguration
    private let tap: CFMachPort
    private let runLoopSource: CFRunLoopSource
    private var drag: DragState = .idle
    private var contacts: [UInt: ContactState] = [:]
    private var pressedKeys: [CGKeyCode: PressedKey] = [:]
    private var swallowedClick = false
    private var lastWindowUpdate: Double = 0
    private(set) var trackpadCount = 0
    private(set) var lastAction = "No shortcut used yet"
    private(set) var touchFrameCount = 0

    init(configuration: AppConfiguration) throws {
        self.configuration = configuration
        let mask = eventMask(.keyDown) | eventMask(.keyUp) | eventMask(.flagsChanged)
            | eventMask(.mouseMoved) | eventMask(.leftMouseDragged) | eventMask(.rightMouseDragged)
            | eventMask(.otherMouseDragged) | eventMask(.leftMouseDown) | eventMask(.leftMouseUp)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                         place: .headInsertEventTap,
                                         options: .defaultTap,
                                         eventsOfInterest: mask,
                                         callback: inputEventCallback,
                                         userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw InputStartError.eventTapUnavailable
        }
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func startTrackpad() {
        contacts.removeAll()
        trackpadCount = Int(TrackpadStart(trackpadFrameCallback))
    }

    func stop() {
        TrackpadStop()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFMachPortInvalidate(tap)
        drag = .idle
        contacts.removeAll()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            drag = .idle
            contacts.removeAll()
            CGEvent.tapEnable(tap: tap, enable: true)
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == generatedEventMarker {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown || type == .keyUp {
            return handleKey(type: type, event: event)
        }
        if type == .leftMouseUp && swallowedClick {
            swallowedClick = false
            return nil
        }
        if type == .leftMouseDown {
            swallowedClick = false
            let now = Double(event.timestamp) / 1_000_000_000
            if NSEvent(cgEvent: event)?.subtype == .touch && hasThreeFingers(at: now),
               let rule = matchingRule(.trackpad(.threeFingerClick)) {
                swallowedClick = true
                performAction(rule)
                return nil
            }
        }
        if type == .leftMouseDragged && swallowedClick {
            return nil
        }
        handleWindowControl(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    func handle(frame: TrackpadFrame) {
        touchFrameCount += 1
        let key = UInt(frame.device)
        let previous = contacts[key]?.swipe ?? .idle
        let point = CGPoint(x: frame.x, y: frame.y)
        let swipe = nextSwipe(previous, count: Int(frame.count), point: point, timestamp: frame.timestamp)
        contacts[key] = ContactState(count: Int(frame.count), timestamp: frame.timestamp, swipe: swipe)
    }

    private func nextSwipe(_ state: SwipeState, count: Int, point: CGPoint, timestamp: Double) -> SwipeState {
        if count == 0 { return .idle }
        switch state {
        case .idle:
            if count == 4 { return .tracking(origin: point, timestamp: timestamp) }
            return count > 4 ? .consumed : .idle
        case .tracking(let origin, let start):
            guard count == 4, timestamp - start <= 1.5 else { return .consumed }
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            if abs(dx) > 0.12 && abs(dx) > abs(dy) { return .consumed }
            if dy > 0.12 { return .consumed }
            if dy < -0.16 && -dy > abs(dx) * 1.5 {
                if let rule = matchingRule(.trackpad(.fourFingerSwipeDown)) { performAction(rule) }
                return .consumed
            }
            return state
        case .consumed:
            return .consumed
        }
    }

    private func hasThreeFingers(at timestamp: Double) -> Bool {
        for state in contacts.values {
            if state.count == 3 && abs(timestamp - state.timestamp) < 0.15 {
                return true
            }
        }
        return false
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            switch pressedKeys.removeValue(forKey: keyCode) {
            case .replaced(let chord): replaceKey(event, with: chord)
            case .consumed: return nil
            case nil: break
            }
            return Unmanaged.passUnretained(event)
        }
        switch pressedKeys[keyCode] {
        case .replaced(let chord):
            replaceKey(event, with: chord)
            return Unmanaged.passUnretained(event)
        case .consumed: return nil
        case nil: break
        }
        if let recorder = NSApplication.shared.keyWindow?.firstResponder as? RecorderButton,
           recorder.isRecording, let nativeEvent = NSEvent(cgEvent: event) {
            recorder.keyDown(with: nativeEvent)
            pressedKeys[keyCode] = .consumed
            return nil
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return Unmanaged.passUnretained(event)
        }
        let trigger = ShortcutTrigger.keyboard(KeyChord(keyCode: keyCode, modifiers: modifierKeys(event.flags)))
        guard let rule = matchingRule(trigger) else { return Unmanaged.passUnretained(event) }
        lastAction = "\(rule.trigger.label) → \(rule.action.label)"
        switch rule.action {
        case .sendShortcut(let chord):
            pressedKeys[keyCode] = .replaced(chord)
            replaceKey(event, with: chord)
            return Unmanaged.passUnretained(event)
        case .minimizeWindow:
            pressedKeys[keyCode] = .consumed
            performAction(rule)
            return nil
        }
    }

    private func matchingRule(_ trigger: ShortcutTrigger) -> ShortcutRule? {
        let application = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return configuration.matchingRule(trigger, application: application)
    }

    private func performAction(_ rule: ShortcutRule) {
        switch rule.action {
        case .sendShortcut(let chord): postShortcut(chord)
        case .minimizeWindow:
            if let point = CGEvent(source: nil)?.location, let target = WindowTarget.underPointer(point) {
                _ = target.minimize()
            }
        }
        lastAction = "\(rule.trigger.label) → \(rule.action.label)"
    }

    private func handleWindowControl(type: CGEventType, event: CGEvent) {
        let modifiers = event.flags.intersection(shortcutModifiers)
        let operation: WindowOperation
        if modifiers == modifierFlags(configuration.windows.moveModifiers) {
            operation = .move
        } else if modifiers == modifierFlags(configuration.windows.resizeModifiers) {
            operation = .resize
        } else {
            if case .active(let session) = drag {
                session.apply(at: event.location)
            }
            drag = .idle
            return
        }

        switch drag {
        case .idle:
            armDrag(operation: operation, point: event.location)
        case .armed(let session):
            if session.operation != operation {
                armDrag(operation: operation, point: event.location)
            } else if hypot(event.location.x - session.origin.x, event.location.y - session.origin.y) >= Double(configuration.windows.threshold) {
                if configuration.windows.raiseWindow { session.target.raise() }
                session.apply(at: event.location)
                drag = .active(session)
                lastWindowUpdate = Double(event.timestamp) / 1_000_000_000
                lastAction = operation == .move ? "Fn → Move window" : "Fn-Shift → Resize window"
            }
        case .active(let session):
            if session.operation != operation {
                session.apply(at: event.location)
                armDrag(operation: operation, point: event.location)
            } else {
                let now = Double(event.timestamp) / 1_000_000_000
                if now - lastWindowUpdate >= 1.0 / 120 {
                    session.apply(at: event.location)
                    lastWindowUpdate = now
                }
            }
        }
    }

    private func armDrag(operation: WindowOperation, point: CGPoint) {
        guard let target = WindowTarget.underPointer(point), target.supports(operation) else {
            drag = .idle
            return
        }
        drag = .armed(WindowDrag(target: target, operation: operation, origin: point))
    }
}

private func eventMask(_ type: CGEventType) -> CGEventMask {
    CGEventMask(1) << type.rawValue
}

private func replaceKey(_ event: CGEvent, with replacement: KeyChord) {
    event.setIntegerValueField(.keyboardEventKeycode, value: Int64(replacement.keyCode))
    event.flags = modifierFlags(replacement.modifiers).union(event.flags.intersection(.maskAlphaShift))
}

private func postShortcut(_ chord: KeyChord) {
    guard let application = NSWorkspace.shared.frontmostApplication,
          let source = CGEventSource(stateID: .privateState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: false) else { return }
    down.flags = modifierFlags(chord.modifiers)
    up.flags = modifierFlags(chord.modifiers)
    down.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
    up.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
    down.postToPid(application.processIdentifier)
    up.postToPid(application.processIdentifier)
}

private func inputEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    appController.handle(type: type, event: event)
}

private func trackpadFrameCallback(_ frame: TrackpadFrame) {
    appController.handle(frame: frame)
}
