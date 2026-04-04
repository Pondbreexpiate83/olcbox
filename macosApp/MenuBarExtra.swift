import SwiftUI
import NetworkExtension

class MenuBarExtra: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var vpnManager: MacosVpnManager

    init(vpnManager: MacosVpnManager) {
        self.vpnManager = vpnManager
        super.init()
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "VPN")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
            updateMenuBarIcon()
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView().environmentObject(vpnManager))

        // Observe VPN status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarIcon),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    @objc private func updateMenuBarIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }

            switch self.vpnManager.connectionState {
            case .connected:
                button.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "VPN Connected")
                button.contentTintColor = .systemGreen
            case .connecting:
                button.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "VPN Connecting")
                button.contentTintColor = .systemOrange
            case .disconnected:
                button.image = NSImage(systemSymbolName: "shield.slash", accessibilityDescription: "VPN Disconnected")
                button.contentTintColor = .systemGray
            case .disconnecting:
                button.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "VPN Disconnecting")
                button.contentTintColor = .systemOrange
            case .invalid:
                button.image = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: "VPN Error")
                button.contentTintColor = .systemRed
            @unknown default:
                button.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "VPN Unknown")
                button.contentTintColor = .systemGray
            }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var vpnManager: MacosVpnManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 15) {
            header

            Divider()

            statusInfo

            Divider()

            serverSelector

            Divider()

            connectButton

            Spacer().frame(height: 10)
        }
        .padding()
        .frame(minWidth: 280)
    }

    private var header: some View {
        HStack {
            Image(systemName: "shield.fill")
                .foregroundColor(.accentColor)
            Text("Turnbox VPN")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var statusInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline)
            }

            if vpnManager.isConnected {
                Text("Connected to \(vpnManager.connectedServerIP)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Ping:")
                    .font(.caption)
                Text(vpnManager.lastPing)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serverSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server")
                .font(.caption)
                .foregroundColor(.secondary)

            // For now, show placeholder. Will populate from KMP store
            Picker("", selection: .constant("")) {
                Text("Select server...")
                    .tag("")
            }
            .pickerStyle(.menu)
            .disabled(true)
        }
    }

    private var connectButton: some View {
        Button(action: toggleConnection) {
            HStack {
                if vpnManager.connectionState == .connecting || vpnManager.connectionState == .disconnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Image(systemName: vpnManager.isConnected ? "power" : "power.circle")
                }

                Text(vpnManager.isConnected ? "Disconnect" : "Connect")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(vpnManager.connectionState == .connecting || vpnManager.connectionState == .disconnecting)
    }

    private func toggleConnection() {
        if vpnManager.isConnected {
            vpnManager.stopVpn()
        } else {
            vpnManager.startVpn()
        }
    }

    private var statusColor: Color {
        switch vpnManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnecting: return .orange
        case .disconnected: return .gray
        case .invalid: return .red
        @unknown default: return .gray
        }
    }

    private var statusText: String {
        switch vpnManager.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnecting: return "Disconnecting..."
        case .disconnected: return "Disconnected"
        case .invalid: return "Error"
        @unknown default: return "Unknown"
        }
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .environmentObject(MacosVpnManager())
    }
}
