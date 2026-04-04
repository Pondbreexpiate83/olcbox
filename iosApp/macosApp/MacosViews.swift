import AppKit
import SwiftUI

private enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Connections"
        case .settings: return "Settings"
        case .logs: return "Logs"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "shield.fill"
        case .settings: return "slider.horizontal.3"
        case .logs: return "list.bullet.rectangle.portrait"
        }
    }
}

struct MacosRootView: View {
    @ObservedObject var viewModel: MacosAppViewModel
    @ObservedObject var vpnManager: MacosVpnManager
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationTitle("Turnbox")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard:
                    DashboardView(viewModel: viewModel, vpnManager: vpnManager)
                case .settings:
                    SettingsView(viewModel: viewModel)
                case .logs:
                    LogsView(viewModel: viewModel, vpnManager: vpnManager)
                }
            }
            .frame(minWidth: 700, minHeight: 500)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .underPageBackgroundColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StatusBadge(
                    state: vpnManager.connectionState,
                    connectedServerIP: vpnManager.connectedServerIP
                )
            }
        }
    }
}

struct MenuBarQuickControlsView: View {
    @ObservedObject var viewModel: MacosAppViewModel
    @ObservedObject var vpnManager: MacosVpnManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Turnbox", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            StatusBadge(
                state: vpnManager.connectionState,
                connectedServerIP: vpnManager.connectedServerIP
            )

            Picker("Server", selection: Binding(
                get: { viewModel.configState.selectedServerId },
                set: { viewModel.selectServer($0) }
            )) {
                ForEach(viewModel.configState.availableServers) { server in
                    Text(server.title).tag(server.id)
                }
            }
            .labelsHidden()
            .frame(width: 230)

            Button(vpnManager.isConnected ? "Disconnect" : "Connect") {
                viewModel.toggleVpn()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()

            Button("Open Turnbox") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

private struct DashboardView: View {
    @ObservedObject var viewModel: MacosAppViewModel
    @ObservedObject var vpnManager: MacosVpnManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Secure Route")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Route selected apps through TURN + Hysteria using a native packet tunnel.")
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            viewModel.toggleVpn()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: vpnManager.isConnected ? "power.circle.fill" : "bolt.horizontal.fill")
                                .font(.system(size: 24, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vpnManager.isConnected ? "Disconnect" : "Connect")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                Text(vpnManager.isConnected ? "Tunnel is active" : "Start packet tunnel")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: vpnManager.isConnected
                                            ? [Color.green.opacity(0.82), Color.blue.opacity(0.72)]
                                            : [Color.accentColor.opacity(0.9), Color.cyan.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .cardStyle()

                HStack(alignment: .top, spacing: 16) {
                    MetricCard(
                        title: "Status",
                        symbol: "network",
                        tint: statusTint(for: vpnManager.connectionState)
                    ) {
                        StatusBadge(
                            state: vpnManager.connectionState,
                            connectedServerIP: vpnManager.connectedServerIP
                        )
                    }

                    MetricCard(
                        title: "Ping",
                        symbol: "bolt.horizontal.fill",
                        tint: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(vpnManager.lastPing.map { "\($0) ms" } ?? "No data")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                            Button("Refresh Ping") {
                                viewModel.refreshPing()
                            }
                            .buttonStyle(.link)
                        }
                    }

                    MetricCard(
                        title: "Probe",
                        symbol: "waveform.path.ecg.rectangle",
                        tint: .purple
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            if vpnManager.isCheckingConnection {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Checking route...")
                                }
                            } else {
                                Text(viewModel.lastConnectionCheck.map { "\($0) ms" } ?? "Idle")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                            }

                            Button("Check Connection") {
                                viewModel.runConnectionCheck()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Current Server")
                        .font(.headline)

                    if let selected = viewModel.configState.availableServers.first(where: { $0.id == viewModel.configState.selectedServerId }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selected.title)
                                .font(.title3.weight(.semibold))
                            Text(selected.server)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Server Selected",
                            systemImage: "icloud.slash",
                            description: Text("Choose or create a server in Settings.")
                        )
                    }
                }
                .cardStyle()
            }
            .padding(24)
        }
        .onAppear {
            viewModel.startDashboardPingRefresh()
        }
        .onDisappear {
            viewModel.stopDashboardPingRefresh()
        }
    }

    private func statusTint(for state: PacketTunnelConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnecting: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: MacosAppViewModel

    var body: some View {
        Form {
            Section("Profiles") {
                Picker("Server", selection: Binding(
                    get: { viewModel.configState.selectedServerId },
                    set: { viewModel.selectServer($0) }
                )) {
                    Text("None").tag("")
                    ForEach(viewModel.configState.availableServers) { server in
                        Text(server.title).tag(server.id)
                    }
                }

                HStack {
                    Button("Save") {
                        Task { try? await viewModel.save() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Delete Selected") {
                        viewModel.deleteSelectedServer()
                    }
                    .disabled(viewModel.configState.selectedServerId.isEmpty)
                }
            }

            Section("Hysteria") {
                TextField("Name", text: Binding(
                    get: { viewModel.configState.hysteriaConfig.name },
                    set: { viewModel.updateHysteria(name: $0) }
                ))
                TextField("Server", text: Binding(
                    get: { viewModel.configState.hysteriaConfig.server },
                    set: { viewModel.updateHysteria(server: $0) }
                ))
                SecureField("Password", text: Binding(
                    get: { viewModel.configState.hysteriaConfig.password },
                    set: { viewModel.updateHysteria(password: $0) }
                ))
                TextField("SNI", text: Binding(
                    get: { viewModel.configState.hysteriaConfig.sni },
                    set: { viewModel.updateHysteria(sni: $0) }
                ))
                Toggle("Insecure TLS", isOn: Binding(
                    get: { viewModel.configState.hysteriaConfig.insecure },
                    set: { viewModel.updateHysteria(insecure: $0) }
                ))
            }

            Section("TURN Settings") {
                Toggle("Enabled", isOn: Binding(
                    get: { viewModel.configState.turnConfig.enabled },
                    set: { viewModel.updateTurn(enabled: $0) }
                ))

                Picker("Link Type", selection: Binding(
                    get: { viewModel.configState.selectedTurnType },
                    set: { viewModel.selectTurnType($0) }
                )) {
                    Text("VK").tag("vk")
                    Text("Yandex").tag("yandex")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)

                TextField("Peer", text: Binding(
                    get: { viewModel.configState.turnConfig.peer },
                    set: { viewModel.updateTurn(peer: $0) }
                ))
                TextField("Link", text: Binding(
                    get: { viewModel.configState.turnConfig.link },
                    set: { viewModel.updateTurn(link: $0) }
                ))
                TextField("User", text: Binding(
                    get: { viewModel.configState.turnConfig.user },
                    set: { viewModel.updateTurn(user: $0) }
                ))
                SecureField("Pass", text: Binding(
                    get: { viewModel.configState.turnConfig.pass },
                    set: { viewModel.updateTurn(pass: $0) }
                ))
                TextField("Listen", text: Binding(
                    get: { viewModel.configState.turnConfig.listen },
                    set: { viewModel.updateTurn(listen: $0) }
                ))
                TextField("Threads", text: Binding(
                    get: { String(Int(viewModel.configState.turnConfig.threads)) },
                    set: { viewModel.updateTurn(threads: Int($0) ?? 8) }
                ))
                Toggle("UDP", isOn: Binding(
                    get: { viewModel.configState.turnConfig.udp },
                    set: { viewModel.updateTurn(udp: $0) }
                ))
                Toggle("No DTLS", isOn: Binding(
                    get: { viewModel.configState.turnConfig.noDtls },
                    set: { viewModel.updateTurn(noDtls: $0) }
                ))
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct LogsView: View {
    @ObservedObject var viewModel: MacosAppViewModel
    @ObservedObject var vpnManager: MacosVpnManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Runtime Log")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Copy Logs") {
                    viewModel.copyLogs()
                }
                Button("Clear") {
                    viewModel.clearLogs()
                }
            }
            .padding(20)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(vpnManager.logs.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: vpnManager.logs.count) { _, _ in
                    guard let lastIndex = vpnManager.logs.indices.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct StatusBadge: View {
    let state: PacketTunnelConnectionState
    let connectedServerIP: String?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let connectedServerIP, state == .connected {
                    Text(connectedServerIP)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnecting: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var title: String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnecting: return "Disconnecting..."
        case .failed: return "Failed"
        case .disconnected: return "Disconnected"
        }
    }
}

private struct MetricCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint)
                .font(.headline)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .cardStyle()
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15))
            )
    }
}
