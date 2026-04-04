import SwiftUI
import NetworkExtension

@main
struct TurnboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vpnManager = MacosVpnManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vpnManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(vpnManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarExtra: MenuBarExtra?
    var vpnManager: MacosVpnManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        vpnManager = MacosVpnManager()
        menuBarExtra = MenuBarExtra(vpnManager: vpnManager!)

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }

        // Hide the main window initially if you want app to be menu bar only
        // NSApp.hide(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running in menu bar
    }
}
