import SwiftUI
import NetworkExtension

struct ContentView: View {
    @StateObject private var vpnManager = MacosVpnManager()
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case settings = "Settings"
        case logs = "Logs"

        var icon: String {
            switch self {
            case .dashboard: "house.fill"
            case .settings: "gear"
            case .logs: "list.bullet"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Turnbox VPN")
            .frame(minWidth: 150)
        } detail: {
            detailView
                .frame(minWidth: 550, minHeight: 400)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .settings:
            SettingsView()
        case .logs:
            LogsView()
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?
            .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var vpnManager: MacosVpnManager

    var body: some View {
        VStack(spacing: 30) {
            statusCard
            connectionToggle
            pingCard
            checkConnectionCard
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusCard: some View {
        VStack(spacing: 15) {
            Image(systemName: vpnManager.isConnected ? "shield.fill" : "shield.slash")
                .font(.system(size: 60))
                .foregroundColor(statusColor)

            Text(statusText)
                .font(.title2)
                .fontWeight(.semibold)

            if vpnManager.isConnected {
                Text("IP: \(vpnManager.connectedServerIP)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(25)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var connectionToggle: some View {
        Toggle(isOn: $vpnManager.isConnected) {
            EmptyView()
        }
        .toggleStyle(ConnectToggleStyle())
        .onChange(of: vpnManager.isConnected) { newValue in
            if newValue {
                vpnManager.startVpn()
            } else {
                vpnManager.stopVpn()
            }
        }
        .disabled(vpnManager.connectionState == .connecting || vpnManager.connectionState == .disconnecting)
    }

    private var pingCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Ping")
                    .font(.headline)
                Spacer()
                Text(vpnManager.lastPing)
                    .font(.title3)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var checkConnectionCard: some View {
        VStack(spacing: 10) {
            HStack {
                if vpnManager.isCheckingConnection {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking connection...")
                } else {
                    Text("Connection Check")
                    Spacer()
                    Button("Check") {
                        Task {
                            await vpnManager.checkConnection()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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

struct ConnectToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "power.circle.fill" : "power.circle")
                .font(.system(size: 80))
                .foregroundColor(configuration.isOn ? .green : .gray)
                .scaleEffect(configuration.isOn ? 1.0 : 0.9)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var vpnManager: MacosVpnManager
    @State private var selectedServerId: String = ""
    @State private var server: String = ""
    @State private var password: String = ""
    @State private var sni: String = ""
    @State private var insecure: Bool = true
    @State private var turnEnabled: Bool = false
    @State private var turnType: String = "custom"
    @State private var turnLink: String = ""
    @State private var turnUser: String = ""
    @State private var turnPass: String = ""

    var body: some View {
        Form {
            serverSection
            turnSection
            saveButton
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadCurrentConfig()
        }
    }

    private var serverSection: some View {
        Section {
            TextField("Server", text: $server)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            TextField("SNI (optional)", text: $sni)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .help("Leave empty to use server hostname as SNI")

            Toggle("Insecure (skip TLS verification)", isOn: $insecure)
        } header: {
            Text("Hysteria Server")
                .font(.headline)
        }
    }

    private var turnSection: some View {
        Section {
            Toggle("Enable TURN Proxy", isOn: $turnEnabled)

            if turnEnabled {
                Picker("Type", selection: $turnType) {
                    Text("Custom").tag("custom")
                    Text("VK").tag("vk")
                    Text("Yandex").tag("yandex")
                }
                .pickerStyle(SegmentedPickerStyle())

                if turnType == "custom" {
                    TextField("TURN Server", text: .constant("turn:relay.turnbox.org:3478"))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(true)

                    TextField("Username", text: $turnUser)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    SecureField("Password", text: $turnPass)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    TextField("Invite Link", text: $turnLink)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .help("Paste VK call link or Yandex Telemost link")
                }
            }
        } header: {
            Text("TURN Settings")
                .font(.headline)
        }
    }

    private var saveButton: some View {
        Button("Save Configuration") {
            Task {
                await saveConfig()
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
    }

    private func loadCurrentConfig() {
        // Implementation will load from KMP store
    }

    private func saveConfig() async {
        // Implementation will save to KMP store
        vpnManager.addLog("Configuration saved")
    }
}

struct LogsView: View {
    @EnvironmentObject private var vpnManager: MacosVpnManager
    @State private var autoScroll = true
    @Namespace private var bottomID

    var body: some View {
        VStack(spacing: 10) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(vpnManager.logs, id: \.self) { log in
                            Text(log)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .id(log)
                        }
                        .id(bottomID)
                    }
                    .padding(.horizontal)
                }
                .onChange(of: vpnManager.logs) { _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo(bottomID)
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Toggle("Auto-scroll", isOn: $autoScroll)

            Spacer()

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vpnManager.copyLogs(), forType: .string)
            }

            Button("Clear") {
                vpnManager.clearLogs()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MacosVpnManager())
    }
}
