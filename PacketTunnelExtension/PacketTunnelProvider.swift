import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = OSLog(subsystem: "org.turnbox.app.macos", category: "PacketTunnel")
    private var appGroupId: String = "group.org.turnbox.app.shared"
    private var selectedServerId: String = ""

    // Process management
    private var vkturnProcess: Process?
    private var hysteriaProcess: Process?
    private var tun2socksProcess: Process?

    // File paths
    private var tempConfigPath: String?
    private var turnListenAddress: String?

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("Starting tunnel...", log: log, type: .info)

        // Extract configuration from providerConfiguration
        guard let providerConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = providerConfiguration.providerConfiguration else {
            os_log("Invalid provider configuration", log: log, type: .error)
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid provider configuration"]))
            return
        }

        if let appGroup = providerConfig["appGroupId"] as? String {
            appGroupId = appGroup
        }

        if let serverId = providerConfig["selectedServerId"] as? String {
            selectedServerId = serverId
        }

        os_log("App Group: %{public}@", log: log, type: .info, appGroupId)

        Task {
            do {
                try await startVPNConnection()
                os_log("VPN connection established", log: log, type: .info)
                completionHandler(nil)
            } catch {
                os_log("VPN connection failed: %{public}@", log: log, type: .error, error.localizedDescription)
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("Stopping tunnel with reason: %{public}d", log: log, type: .info, reason.rawValue)

        cleanupProcesses()
        cleanupTempFiles()

        os_log("Tunnel stopped", log: log, type: .info)
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        os_log("Received app message", log: log, type: .debug)

        // Handle messages from the app if needed
        // For now, just echo back
        completionHandler?(messageData)
    }

    // MARK: - VPN Connection Logic

    func startVPNConnection() async throws {
        // Load configurations from app group
        let (hysteriaConfig, turnConfig) = try await loadConfigurations()

        guard !hysteriaConfig.server.isEmpty else {
            throw NSError(domain: "PacketTunnelProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "No server configured"])
        }

        // Start TURN if enabled
        let effectiveServer: String
        if turnConfig.enabled {
            effectiveServer = try await startTurnProxy(turnConfig: turnConfig, server: hysteriaConfig.server)
        } else {
            effectiveServer = hysteriaConfig.server
        }

        // Start Hysteria with the effective server
        try await startHysteria(hysteriaConfig: hysteriaConfig, server: effectiveServer)

        // Wait for Hysteria SOCKS5 to be ready
        try await waitForHysteria()

        // Start tun2socks to bridge Hysteria SOCKS5 to TUN interface
        try await startTun2Socks()

        // Configure network settings
        try await configureNetworkSettings()
    }

    // MARK: - Configuration Loading

    func loadConfigurations() async throws -> (HysteriaConfig, TurnConfig) {
        // This would typically load from the app group shared directory
        // For now, return defaults
        return (
            HysteriaConfig(
                server: "",
                name: "",
                password: "",
                sni: "",
                insecure: true
            ),
            TurnConfig()
        )
    }

    // MARK: - TURN Proxy

    func startTurnProxy(turnConfig: TurnConfig, server: String) async throws -> String {
        guard let libvkturn = Bundle.main.path(forResource: "libvkturn", ofType: "") else {
            throw NSError(domain: "PacketTunnelProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "libvkturn not found"])
        }

        let listenAddress = "127.0.0.1:\(Int.random(in: 10000...20000))"
        turnListenAddress = listenAddress

        var arguments = [
            "-peer", server,
            "-listen", listenAddress,
            "-n", "1"
        ]

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

        os_log("Starting TURN: %{public}@ with args: %{public}@", log: log, type: .info, libvkturn, arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: libvkturn)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        vkturnProcess = process

        // Wait briefly for TURN to start listening
        try await Task.sleep(nanoseconds: 500_000_000)

        os_log("TURN proxy started, listening on: %{public}@", log: log, type: .info, listenAddress)
        return listenAddress
    }

    // MARK: - Hysteria

    func startHysteria(hysteriaConfig: HysteriaConfig, server: String) async throws {
        guard let libhysteria = Bundle.main.path(forResource: "libhysteria", ofType: "") else {
            throw NSError(domain: "PacketTunnelProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "libhysteria not found"])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let configName = "hysteria_\(UUID().uuidString).yaml"
        let configPath = tempDir.appendingPathComponent(configName)
        tempConfigPath = configPath.path

        let sni = hysteriaConfig.sni.isEmpty ? server.components(separatedBy: ":").first ?? "" : hysteriaConfig.sni
        let socksPort = 1080 // Standard SOCKS5 port

        let configContent = """
        server: \(server)
        auth: \(hysteriaConfig.password)
        tls:
          sni: \(sni)
          insecure: \(hysteriaConfig.insecure)
        socks5:
          listen: 127.0.0.1:\(socksPort)
        quic:
          handshakeTimeout: 3s
          maxIdleTimeout: 60s
          keepAlivePeriod: 30s
        bandwidth:
          up: 100 mbps
          down: 100 mbps
        """

        try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        os_log("Created Hysteria config: %{public}@", log: log, type: .debug, configPath.path)

        let arguments = ["-c", configPath.path]
        os_log("Starting Hysteria: %{public}@ with args: %{public}@", log: log, type: .info, libhysteria, arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: libhysteria)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        hysteriaProcess = process

        os_log("Hysteria process started", log: log, type: .info)
    }

    func waitForHysteria() async throws {
        guard let process = hysteriaProcess else {
            throw NSError(domain: "PacketTunnelProvider", code: 5, userInfo: [NSLocalizedDescriptionKey: "Hysteria process not started"])
        }

        guard let pipe = process.standardOutput as? Pipe else {
            throw NSError(domain: "PacketTunnelProvider", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid Hysteria output pipe"])
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var connected = false

        while CFAbsoluteTimeGetCurrent() - startTime < 10.0 {
            let data = pipe.fileHandleForReading.availableData

            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                os_log("Hysteria output: %{public}@", log: log, type: .debug, output)

                if output.contains("connected") {
                    connected = true
                    break
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if !connected {
            throw NSError(domain: "PacketTunnelProvider", code: 7, userInfo: [NSLocalizedDescriptionKey: "Hysteria failed to connect within timeout"])
        }

        os_log("Hysteria connected successfully", log: log, type: .info)
    }

    // MARK: - tun2socks

    func startTun2Socks() async throws {
        guard let tun2socks = Bundle.main.path(forResource: "tun2socks", ofType: "") else {
            throw NSError(domain: "PacketTunnelProvider", code: 8, userInfo: [NSLocalizedDescriptionKey: "tun2socks not found"])
        }

        // SOCKS5 is provided by Hysteria on 127.0.0.1:1080
        let arguments = [
            "-tun", "fd://0", // Use file descriptor 0 for the TUN interface
            "-proxy", "socks5://127.0.0.1:1080",
            "-loglevel", "1"
        ]

        os_log("Starting tun2socks: %{public}@ with args: %{public}@", log: log, type: .info, tun2socks, arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tun2socks)
        process.arguments = arguments

        // Pass the file descriptor for the TUN interface
        let tunFd = self.value(forKey: "_tunFileDescriptor") as! Int32
        let pipe = Pipe()
        pipe.fileHandleForWriting.fileDescriptor = tunFd
        process.standardInput = pipe

        try process.run()
        tun2socksProcess = process

        os_log("tun2socks started", log: log, type: .info)
    }

    // MARK: - Network Settings

    func configureNetworkSettings() async throws {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // IPv4 settings
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.0.88.88"], subnetMasks: ["255.255.0.0"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings?.excludedRoutes = []

        // IPv6 settings (optional)
        settings.ipv6Settings = nil

        // DNS settings
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.dnsSettings?.matchDomains = [""]

        // Proxy settings (Hysteria provides SOCKS5 on 127.0.0.1:1080)
        let proxySettings = NEProxySettings()
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: 10808)
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: 10808)
        proxySettings.autoProxyConfigurationEnabled = false
        proxySettings.excludedDomains = []
        settings.proxySettings = proxySettings

        os_log("Applying network settings...", log: log, type: .info)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setTunnelNetworkSettings(settings) { error in
                if let error = error {
                    os_log("Failed to apply network settings: %{public}@", log: self.log, type: .error, error.localizedDescription)
                    continuation.resume(throwing: error)
                } else {
                    os_log("Network settings applied", log: self.log, type: .info)
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Cleanup

    func cleanupProcesses() {
        os_log("Cleaning up processes...", log: log, type: .info)

        vkturnProcess?.terminate()
        hysteriaProcess?.terminate()
        tun2socksProcess?.terminate()

        vkturnProcess = nil
        hysteriaProcess = nil
        tun2socksProcess = nil
    }

    func cleanupTempFiles() {
        os_log("Cleaning up temp files...", log: log, type: .info)

        if let configPath = tempConfigPath {
            try? FileManager.default.removeItem(atPath: configPath)
            tempConfigPath = nil
        }
    }
}

// MARK: - Extensions

extension NEIPv4Route {
    static func `default`() -> NEIPv4Route {
        return NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0")
    }
}
