import Foundation
import NetworkExtension
import Combine
import UserNotifications
import SharedUI

class MacosVpnManager: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var connectionState: NEVPNStatus = .disconnected
    @Published var logs: [String] = []
    @Published var isCheckingConnection: Bool = false
    @Published var lastPing: String = "-"
    @Published var connectedServerIP: String = "-"
    @Published var selectedServerId: String = ""

    // MARK: - Private Properties
    private var vpnManager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()
    private let appGroupId = "group.org.turnbox.app.shared"
    private let maxLogCount = 1000

    // MARK: - Initialization
    override init() {
        super.init()
        setupNotifications()
        loadVPNConfiguration()
    }

    // MARK: - Setup
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: NEVPNStatusDidChangeNotification)
            .compactMap { $0.object as? NETunnelProviderManager }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] manager in
                self?.handleVPNStatusChange(manager.connection.status)
            }
            .store(in: &cancellables)
    }

    // MARK: - VPN Configuration Management
    private func loadVPNConfiguration() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                self?.addLog("Failed to load VPN configurations: \(error.localizedDescription)")
                return
            }

            self?.vpnManager = managers?.first ?? NETunnelProviderManager()
            self?.addLog("VPN configuration loaded")
        }
    }

    private func saveVPNConfiguration(completion: @escaping (Error?) -> Void) {
        guard let vpnManager = vpnManager else {
            completion(NSError(domain: "MacosVpnManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "VPN Manager not initialized"]))
            return
        }

        vpnManager.saveToPreferences { error in
            if let error = error {
                completion(error)
                return
            }
            vpnManager.loadFromPreferences { error in
                completion(error)
            }
        }
    }

    // MARK: - VPN Control
    func startVpn() {
        guard let vpnManager = vpnManager else { return }

        do {
            // Configure the tunnel provider
            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.providerBundleIdentifier = "org.turnbox.app.macos.PacketTunnel"
            protocolConfiguration.serverAddress = "Hysteria2 VPN"

            // Pass app group ID and selected configurations to the extension
            protocolConfiguration.providerConfiguration = [
                "appGroupId": appGroupId,
                "selectedServerId": selectedServerId
            ]

            vpnManager.protocolConfiguration = protocolConfiguration

            // Enable on-demand if needed
            vpnManager.isOnDemandEnabled = false
            vpnManager.isEnabled = true

            // Save configuration and start VPN
            saveVPNConfiguration { [weak self] error in
                if let error = error {
                    self?.addLog("Failed to save VPN config: \(error.localizedDescription)")
                    self?.sendNotification(title: "VPN Error", body: "Failed to save configuration: \(error.localizedDescription)")
                    return
                }

                do {
                    try vpnManager.connection.startVPNTunnel()
                    self?.addLog("VPN connection started")
                } catch {
                    self?.addLog("Failed to start VPN tunnel: \(error.localizedDescription)")
                    self?.sendNotification(title: "VPN Error", body: "Failed to start tunnel: \(error.localizedDescription)")
                }
            }

        } catch {
            addLog("Failed to configure VPN: \(error.localizedDescription)")
            sendNotification(title: "VPN Error", body: "Configuration error: \(error.localizedDescription)")
        }
    }

    func stopVpn() {
        guard let vpnManager = vpnManager else { return }
        vpnManager.connection.stopVPNTunnel()
        addLog("VPN connection stopped")
    }

    // MARK: - Status Handling
    private func handleVPNStatusChange(_ status: NEVPNStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = status
            self?.isConnected = status == .connected

            switch status {
            case .connected:
                self?.addLog("VPN connected")
                self?.sendNotification(title: "VPN Connected", body: "Secure connection established")
                Task {
                    await self?.performPing()
                }
            case .disconnected:
                self?.addLog("VPN disconnected")
                self?.sendNotification(title: "VPN Disconnected", body: "Connection terminated")
            case .connecting:
                self?.addLog("VPN connecting...")
            case .disconnecting:
                self?.addLog("VPN disconnecting...")
            case .invalid:
                self?.addLog("VPN invalid state")
            @unknown default:
                self?.addLog("VPN unknown state")
            }
        }
    }

    // MARK: - Ping and Connection Check
    func performPing() async {
        guard let configStore = getConfigStore() else {
            addLog("Config store not available")
            return
        }

        let state = configStore.state.value
        let hysteriaConfig = state.hysteriaConfig
        let turnConfig = state.turnConfig

        guard !hysteriaConfig.server.isEmpty else {
            addLog("No server configured")
            return
        }

        do {
            if let rtt = try await withTimeout(5) {
                try await KMPPing(turnConfig: turnConfig, hysteriaConfig: hysteriaConfig)
            } {
                let rttString = String(format: "%.0f ms", Double(rtt))
                await MainActor.run {
                    self.lastPing = rttString
                }
                addLog("Ping: \(rttString)")
            } else {
                addLog("Ping timeout")
                await MainActor.run {
                    self.lastPing = "Timeout"
                }
            }
        } catch {
            addLog("Ping error: \(error.localizedDescription)")
            await MainActor.run {
                self.lastPing = "Error"
            }
        }
    }

    func checkConnection() async -> Bool {
        guard let configStore = getConfigStore() else {
            addLog("Config store not available")
            return false
        }

        let state = configStore.state.value
        let hysteriaConfig = state.hysteriaConfig
        let turnConfig = state.turnConfig

        guard !hysteriaConfig.server.isEmpty else {
            addLog("No server configured")
            return false
        }

        await MainActor.run {
            self.isCheckingConnection = true
        }

        defer {
            Task { @MainActor in
                self.isCheckingConnection = false
            }
        }

        do {
            let latency = try await withTimeout(6) {
                try await KMPCheckConnection(turnConfig: turnConfig, hysteriaConfig: hysteriaConfig)
            }

            if let latency = latency {
                let latencyString = String(format: "%.0f ms", Double(latency))
                addLog("Check connection: \(latencyString)")
                return true
            } else {
                addLog("Connection check failed")
                return false
            }
        } catch {
            addLog("Connection check error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Native Binary Execution
    private func executeBinary(at path: String, with arguments: [String]) async throws -> (String, Int32) {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    continuation.resume(returning: (output, process.terminationStatus))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T?) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                return nil
            }

            group.cancelAll()
            return result
        }
    }

    func KMPPing(turnConfig: TurnConfig, hysteriaConfig: HysteriaConfig) async throws -> Long? {
        let server = hysteriaConfig.server
        let randomPort = Int.random(in: 30001...40000)

        guard let libvkturn = Bundle.main.path(forResource: "libvkturn", ofType: "") else {
            throw NSError(domain: "MacosVpnManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "libvkturn not found"])
        }

        var arguments = [
            "-peer", server,
            "-ping",
            "-ping-count", "1",
            "-ping-timeout", "3s",
            "-listen", "127.0.0.1:\(randomPort)"
        ]

        if turnConfig.enabled {
            if !turnConfig.link.isEmpty {
                let isYandex = turnConfig.link.contains("yandex")
                arguments.append(isYandex ? "-yandex-link" : "-vk-link")
                arguments.append(turnConfig.link)
            } else if !turnConfig.user.isEmpty && !turnConfig.pass.isEmpty {
                let turnServer = turnConfig.peer.isEmpty ? "turn:relay.turnbox.org:3478" : turnConfig.peer
                arguments.append(contentsOf: ["-turn-server", turnServer])
                arguments.append(contentsOf: ["-turn-user", turnConfig.user])
                arguments.append(contentsOf: ["-turn-pass", turnConfig.pass])
            }
        }

        addLog("Executing ping: \(libvkturn) \(arguments.joined(separator: " "))")

        let (output, status) = try await executeBinary(at: libvkturn, with: arguments)

        if !output.isEmpty {
            addLog("Ping output: \(output)")
        }

        if status != 0 {
            addLog("Ping failed with status: \(status)")
            return nil
        }

        let pattern = /time=(\d+\.?\d*)ms/
        if let match = output.firstMatch(of: pattern) {
            if let rtt = Double(match.1) {
                return Long(rtt)
            }
        }

        return nil
    }

    func KMPCheckConnection(turnConfig: TurnConfig, hysteriaConfig: HysteriaConfig) async throws -> Long? {
        let server = hysteriaConfig.server
        let tempDir = FileManager.default.temporaryDirectory
        let configName = "temp_check_\(Int.random(in: 0...999)).yaml"
        let configPath = tempDir.appendingPathComponent(configName)

        var turnProcess: Process?
        let turnListen = "127.0.0.1:\(Int.random(in: 10000...20000))"

        guard let libvkturn = Bundle.main.path(forResource: "libvkturn", ofType: "") else {
            throw NSError(domain: "MacosVpnManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "libvkturn not found"])
        }

        guard let libhysteria = Bundle.main.path(forResource: "libhysteria", ofType: "") else {
            throw NSError(domain: "MacosVpnManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "libhysteria not found"])
        }

        let effectiveServer: String

        if turnConfig.enabled {
            var turnArguments = [
                "-peer", server,
                "-listen", turnListen,
                "-n", "1"
            ]

            if !turnConfig.link.isEmpty {
                let isYandex = turnConfig.link.contains("yandex")
                turnArguments.append(isYandex ? "-yandex-link" : "-vk-link")
                turnArguments.append(turnConfig.link)
            }

            addLog("Starting TURN: \(libvkturn) \(turnArguments.joined(separator: " "))")

            turnProcess = Process()
            turnProcess?.executableURL = URL(fileURLWithPath: libvkturn)
            turnProcess?.arguments = turnArguments

            try turnProcess?.run()
            effectiveServer = turnListen

            try await Task.sleep(nanoseconds: 500_000_000)
        } else {
            effectiveServer = server
        }

        let socksPort = Int.random(in: 20001...30000)
        let sni = hysteriaConfig.sni.isEmpty ? server.components(separatedBy: ":").first ?? "" : hysteriaConfig.sni

        let configContent = """
        server: \(effectiveServer)
        auth: \(hysteriaConfig.password)
        tls:
          sni: \(sni)
          insecure: \(hysteriaConfig.insecure)
        socks5:
          listen: 127.0.0.1:\(socksPort)
        quic:
          handshakeTimeout: 3s
        """

        try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        addLog("Created temp config: \(configPath.path)")

        defer {
            try? FileManager.default.removeItem(at: configPath)
            turnProcess?.terminate()
        }

        let hysteriaArguments = ["-c", configPath.path]
        addLog("Starting Hysteria: \(libhysteria) \(hysteriaArguments.joined(separator: " "))")

        let hysteriaProcess = Process()
        hysteriaProcess.executableURL = URL(fileURLWithPath: libhysteria)
        hysteriaProcess.arguments = hysteriaArguments

        let pipe = Pipe()
        hysteriaProcess.standardOutput = pipe
        hysteriaProcess.standardError = pipe

        try hysteriaProcess.run()

        let startTime = CFAbsoluteTimeGetCurrent()
        var connected = false

        while CFAbsoluteTimeGetCurrent() - startTime < 4.0 {
            if pipe.fileHandleForReading.availableData.isEmpty {
                try await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            let data = pipe.fileHandleForReading.availableData
            if let output = String(data: data, encoding: .utf8), output.contains("connected") {
                connected = true
                break
            }
        }

        hysteriaProcess.terminate()
        turnProcess?.terminate()

        if connected {
            let latency = CFAbsoluteTimeGetCurrent() - startTime
            return Long(latency * 1000)
        }

        return nil
    }

    // MARK: - Logging
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"

        print(logEntry)

        Task { @MainActor in
            self.logs.append(logEntry)
            if self.logs.count > self.maxLogCount {
                self.logs.removeFirst(self.logs.count - self.maxLogCount)
            }
        }
    }

    func clearLogs() {
        Task { @MainActor in
            self.logs.removeAll()
        }
    }

    func copyLogs() -> String {
        return logs.joined(separator: "\n")
    }

    // MARK: - KMP Integration
    private func getConfigStore() -> MacosConfigStore? {
        let deps = MacosDependencies()
        return deps.configStore
    }

    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
