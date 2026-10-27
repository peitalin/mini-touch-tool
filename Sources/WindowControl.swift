import AppKit
import ApplicationServices

enum WindowOperation {
    case move
    case resize
}

private enum WindowOwner {
    case thisApp(NSWindow)
    case external(element: AXUIElement, processID: pid_t)
}

struct WindowTarget {
    private let owner: WindowOwner
    let frame: CGRect

    static func underPointer(_ point: CGPoint) -> WindowTarget? {
        if let window = localWindowUnderPointer(point) {
            return WindowTarget(owner: .thisApp(window), frame: hostFrame(window))
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else {
            return nil
        }

        let window: AXUIElement
        if stringAttribute(hit, kAXRoleAttribute) == kAXWindowRole {
            window = hit
        } else if let owner = elementAttribute(hit, kAXWindowAttribute) {
            window = owner
        } else {
            return nil
        }

        AXUIElementSetMessagingTimeout(window, 0.1)
        var processID: pid_t = 0
        guard AXUIElementGetPid(window, &processID) == .success,
              processID != getpid(),
              booleanAttribute(window, "AXFullScreen") != true,
              let frame = windowFrame(window) else {
            return nil
        }
        return WindowTarget(owner: .external(element: window, processID: processID), frame: frame)
    }

    func supports(_ operation: WindowOperation) -> Bool {
        switch (owner, operation) {
        case (.thisApp(let window), .move):
            return window.isMovable
        case (.thisApp(let window), .resize):
            return window.styleMask.contains(.resizable)
        case (.external(let element, _), .move):
            return isSettable(element, kAXPositionAttribute)
        case (.external(let element, _), .resize):
            return isSettable(element, kAXSizeAttribute)
        }
    }

    func raise() {
        switch owner {
        case .thisApp(let window):
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        case .external(let element, let processID):
            NSRunningApplication(processIdentifier: processID)?.activate(options: [])
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    func minimize() -> Bool {
        switch owner {
        case .thisApp(let window):
            guard window.styleMask.contains(.miniaturizable) else { return false }
            window.performMiniaturize(nil)
            return window.isMiniaturized
        case .external(let element, _):
            return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        }
    }

    func move(to point: CGPoint) {
        switch owner {
        case .thisApp(let window):
            window.setFrameOrigin(NSPoint(x: point.x, y: hostScreenHeight() - point.y - window.frame.height))
        case .external(let element, _):
            var point = point
            guard let value = AXValueCreate(.cgPoint, &point) else { return }
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    func resize(to size: CGSize) -> CGSize {
        switch owner {
        case .thisApp(let window):
            let width = min(max(size.width, window.minSize.width), window.maxSize.width)
            let height = min(max(size.height, window.minSize.height), window.maxSize.height)
            var resized = window.frame
            resized.origin.y += resized.height - height
            resized.size = CGSize(width: width, height: height)
            window.setFrame(resized, display: true)
            return window.frame.size
        case .external(let element, _):
            var size = size
            guard let value = AXValueCreate(.cgSize, &size) else { return frame.size }
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
            return windowFrame(element)?.size ?? frame.size
        }
    }
}

private func localWindowUnderPointer(_ point: CGPoint) -> NSWindow? {
    guard let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for record in records {
        guard let layer = record[kCGWindowLayer as String] as? Int, layer == 0,
              let alpha = record[kCGWindowAlpha as String] as? Double, alpha > 0,
              let bounds = record[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point),
              let processID = record[kCGWindowOwnerPID as String] as? pid_t,
              let number = record[kCGWindowNumber as String] as? Int else { continue }
        guard processID == getpid() else { return nil }
        for window in NSApplication.shared.windows where window.windowNumber == number {
            return window.styleMask.contains(.fullScreen) ? nil : window
        }
        return nil
    }
    return nil
}

private func hostScreenHeight() -> CGFloat {
    CGDisplayBounds(CGMainDisplayID()).height
}

private func hostFrame(_ window: NSWindow) -> CGRect {
    let frame = window.frame
    return CGRect(x: frame.minX, y: hostScreenHeight() - frame.maxY, width: frame.width, height: frame.height)
}

struct WindowDrag {
    let target: WindowTarget
    let operation: WindowOperation
    let origin: CGPoint
    let resizeLeft: Bool
    let resizeTop: Bool

    init(target: WindowTarget, operation: WindowOperation, origin: CGPoint) {
        self.target = target
        self.operation = operation
        self.origin = origin
        resizeLeft = origin.x < target.frame.midX
        resizeTop = origin.y < target.frame.midY
    }

    func apply(at point: CGPoint) {
        let delta = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        switch operation {
        case .move:
            target.move(to: CGPoint(x: target.frame.minX + delta.x, y: target.frame.minY + delta.y))
        case .resize:
            let width = max(160, target.frame.width + (resizeLeft ? -delta.x : delta.x))
            let height = max(100, target.frame.height + (resizeTop ? -delta.y : delta.y))
            let actualSize = target.resize(to: CGSize(width: width, height: height))
            if resizeLeft || resizeTop {
                let x = resizeLeft ? target.frame.maxX - actualSize.width : target.frame.minX
                let y = resizeTop ? target.frame.maxY - actualSize.height : target.frame.minY
                target.move(to: CGPoint(x: x, y: y))
            }
        }
    }
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

private func booleanAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
    attribute(element, name) as? Bool
}

private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
}

private func windowFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(),
          CFGetTypeID(size) == AXValueGetTypeID() else { return nil }

    let positionValue = position as! AXValue
    let sizeValue = size as! AXValue
    guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &point),
          AXValueGetValue(sizeValue, .cgSize, &dimensions),
          point.x.isFinite, point.y.isFinite,
          dimensions.width.isFinite, dimensions.height.isFinite,
          dimensions.width > 0, dimensions.height > 0 else { return nil }
    return CGRect(origin: point, size: dimensions)
}
