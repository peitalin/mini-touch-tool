import AppKit
import ApplicationServices
import ServiceManagement

let application = NSApplication.shared

if CommandLine.arguments.contains("--diagnose") {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    print("Mini Touch Tool \(version)")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Input Monitoring: \(CGPreflightListenEventAccess())")
    print("BetterTouchTool running: \(betterTouchToolIsRunning())")
    print("Launch at Login status: \(SMAppService.mainApp.status.rawValue)")
    print("Trackpad devices: \(TrackpadStart(diagnosticFrameCallback))")
    TrackpadStop()
    exit(0)
}

let appController = AppController()
application.delegate = appController
application.setActivationPolicy(.accessory)
application.run()

func diagnosticFrameCallback(_ frame: TrackpadFrame) {}
