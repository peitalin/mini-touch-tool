import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
import SwiftUI

private enum AppState {
    case stopped
    case suspended
    case paused
    case waitingForAccess
    case betterTouchToolRunning
    case running(InputEngine)
    case failed
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState = .stopped
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private(set) var configuration = loadConfiguration()
    private lazy var settingsModel = SettingsModel(controller: self, configuration: configuration)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Mini Touch Tool")
        statusItem.button?.setAccessibilityLabel("Mini Touch Tool")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showSettings)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(wakeInput), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionLocked), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(restartInput), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let firstLaunch = !UserDefaults.standard.bool(forKey: "completedFirstLaunch")
        if firstLaunch {
            UserDefaults.standard.set(true, forKey: "completedFirstLaunch")
            enableLogin()
        }
        reconcile()
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) { stopInput() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        updatePermissionTimer()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard case .running(let engine) = state else { return Unmanaged.passUnretained(event) }
        return engine.handle(type: type, event: event)
    }

    func handle(frame: TrackpadFrame) {
        guard case .running(let engine) = state else { return }
        engine.handle(frame: frame)
    }

    func applyConfiguration(_ configuration: AppConfiguration) {
        self.configuration = configuration
        restartInput()
    }

    private func stopInput() {
        if case .running(let engine) = state { engine.stop() }
        state = .stopped
    }

    private func reconcile() {
        if case .suspended = state { return }
        if UserDefaults.standard.bool(forKey: "paused") {
            stopInput()
            state = .paused
        } else if betterTouchToolIsRunning() {
            stopInput()
            state = .betterTouchToolRunning
        } else if !AXIsProcessTrusted() || !CGPreflightListenEventAccess() {
            stopInput()
            state = .waitingForAccess
        } else if case .running = state {
            refreshView()
            return
        } else {
            do {
                let engine = try InputEngine(configuration: configuration)
                state = .running(engine)
                engine.startTrackpad()
            } catch {
                state = .failed
            }
        }
        updatePermissionTimer()
        refreshView()
    }

    private func updatePermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if case .waitingForAccess = state {
            permissionTimer = Timer.scheduledTimer(timeInterval: 2, target: self,
                                                    selector: #selector(permissionsChanged), userInfo: nil, repeats: true)
        }
    }

    private func refreshView() {
        switch state {
        case .stopped: settingsModel.status = "Input stopped"
        case .suspended: settingsModel.status = "Input suspended while the session is locked"
        case .paused: settingsModel.status = "Paused"
        case .waitingForAccess: settingsModel.status = "Allow Accessibility and Input Monitoring in Setup"
        case .betterTouchToolRunning: settingsModel.status = "Quit BetterTouchTool to enable shortcuts"
        case .running: settingsModel.status = "Shortcuts enabled"
        case .failed: settingsModel.status = "Input unavailable. Grant access, then restart input in Setup."
        }
        if case .running(let engine) = state {
            settingsModel.isRunning = true
            switch engine.trackpadCount {
            case -1: settingsModel.detail = "Gesture interface unavailable."
            case 0: settingsModel.detail = "No trackpad. Connect it, then select Restart Input."
            default: settingsModel.detail = "Trackpads: \(engine.trackpadCount). \(engine.lastAction)."
            }
        } else {
            settingsModel.isRunning = false
            settingsModel.detail = ""
        }
        settingsModel.isPaused = UserDefaults.standard.bool(forKey: "paused")
        settingsModel.launchAtLogin = SMAppService.mainApp.status == .enabled
        statusItem.button?.toolTip = "Mini Touch Tool: \(settingsModel.status)"
    }

    private func enableLogin() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            settingsModel.message = "Launch at Login: \(error.localizedDescription)"
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func togglePause() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "paused"), forKey: "paused")
        reconcile()
    }

    func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            do { try SMAppService.mainApp.unregister() }
            catch { settingsModel.message = error.localizedDescription }
        } else {
            enableLogin()
        }
        refreshView()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        reconcile()
    }

    func requestInputMonitoring() {
        CGRequestListenEventAccess()
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        reconcile()
    }

    func openTrackpadSettings() {
        openSettings("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
    }

    @objc private func applicationsChanged() { reconcile() }
    @objc private func permissionsChanged() { reconcile() }

    @objc private func sessionLocked() {
        stopInput()
        state = .suspended
        permissionTimer?.invalidate()
        permissionTimer = nil
        refreshView()
    }

    @objc private func wakeInput() {
        if case .suspended = state { return }
        restartInput()
    }

    @objc func restartInput() {
        stopInput()
        reconcile()
    }

    @objc private func showSettings() {
        reconcile()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: settingsModel))
            let window = NSWindow(contentViewController: controller)
            window.title = "Mini Touch Tool"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 860, height: 640))
            window.minSize = NSSize(width: 810, height: 610)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("MiniTouchToolSettings")
            window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

func betterTouchToolIsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.hegenberg.BetterTouchTool").isEmpty
}

private func openSettings(_ address: String) {
    guard let url = URL(string: address) else { return }
    NSWorkspace.shared.open(url)
}
