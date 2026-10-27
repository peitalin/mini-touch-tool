import AppKit
import ApplicationServices

enum WindowOperation {
    case move
    case resize
}

struct WindowTarget {
    let element: AXUIElement
    let processID: pid_t
    let frame: CGRect

    static func underPointer(_ point: CGPoint) -> WindowTarget? {
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
        return WindowTarget(element: window, processID: processID, frame: frame)
    }

    func supports(_ operation: WindowOperation) -> Bool {
        switch operation {
        case .move:
            return isSettable(element, kAXPositionAttribute)
        case .resize:
            return isSettable(element, kAXSizeAttribute)
        }
    }

    func raise() {
        NSRunningApplication(processIdentifier: processID)?.activate(options: [])
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func minimize() -> Bool {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    func move(to point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func resize(to size: CGSize) -> CGSize {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return frame.size }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        return windowFrame(element)?.size ?? frame.size
    }
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
