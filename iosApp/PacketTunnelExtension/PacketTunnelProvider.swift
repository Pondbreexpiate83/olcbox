import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var runtimeStore: SharedRuntimeStore?
    private var turnProcess: Process?
    private var hysteriaProcess: Process?
    private var tun2SocksProcess: Process?
    private var loggingTasks: [Task<Void, Never>] = []
    private var isHysteriaSocksReady = false

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                let context = try resolveContext()
                let runtimeStore = try SharedRuntimeStore(appGroupId: context.appGroupId)
                self.runtimeStore = runtimeStore

                runtimeStore.clearLogs()
                appendLog("Starting packet tunnel")
                writeStatus(
                    state: .connecting,
                    isConnected: false,
                    connectedServerIP: nil,
                    selectedServerId: context.selectedServerId,
                    lastError: nil
                )

                let hysteriaConfig = try loadHysteriaConfig(context: context, store: runtimeStore)
                let turnConfig = loadTurnConfig(context: context, store: runtimeStore)

                if turnConfig.enabled {
                    turnProcess = try startTurn(
                        store: runtimeStore,
                        turnConfig: turnConfig,
                        hysteriaConfig: hysteriaConfig
                    )
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }

                let runtimeConfigURL = try writeRuntimeHysteriaConfig(
                    store: runtimeStore,
                    turnConfig: turnConfig,
                    hysteriaConfig: hysteriaConfig
                )

                hysteriaProcess = try startHysteria(
                    store: runtimeStore,
                    configURL: runtimeConfigURL
                )
                try await waitForHysteriaReady()

                try await applyNetworkSettings(
                    remoteAddress: runtimeStore.hostDisplay(from: hysteriaConfig.server) ?? "127.0.0.1"
                )

                tun2SocksProcess = try startTun2Socks(store: runtimeStore)
                writeStatus(
                    state: .connected,
                    isConnected: true,
                    connectedServerIP: runtimeStore.hostDisplay(from: hysteriaConfig.server),
                    selectedServerId: context.selectedServerId,
                    lastError: nil
                )
                appendLog("Packet tunnel connected")
                completionHandler(nil)
            } catch {
                appendLog("Tunnel start failed: \(error.localizedDescription)")
                writeStatus(
                    state: .failed,
                    isConnected: false,
                    connectedServerIP: nil,
                    selectedServerId: nil,
                    lastError: error.localizedDescription
                )
                cleanupProcesses()
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        appendLog("Stopping packet tunnel")
        writeStatus(
            state: .disconnecting,
            isConnected: false,
            connectedServerIP: nil,
            selectedServerId: nil,
            lastError: nil
        )
        cleanupProcesses()
        writeStatus(
            state: .disconnected,
            isConnected: false,
            connectedServerIP: nil,
            selectedServerId: nil,
            lastError: nil
        )
        completionHandler()
    }

    private func resolveContext() throws -> ProviderContext {
        let providerProtocol = protocolConfiguration as? NETunnelProviderProtocol
        let providerConfiguration = providerProtocol?.providerConfiguration ?? [:]

        let appGroupId = (providerConfiguration["appGroupId"] as? String)
            ?? TurnboxRuntimeDefaults.appGroupId
        let selectedServerId = (providerConfiguration["selectedServerId"] as? String) ?? ""
        let selectedTurnType = (providerConfiguration["selectedTurnType"] as? String) ?? "custom"

        return ProviderContext(
            appGroupId: appGroupId,
            selectedServerId: selectedServerId,
            selectedTurnType: selectedTurnType
        )
    }

    private func loadHysteriaConfig(
        context: ProviderContext,
        store: SharedRuntimeStore
    ) throws -> HysteriaConfigPayload {
        guard let config = store.loadHysteriaConfig(id: context.selectedServerId) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return config
    }

    private func loadTurnConfig(
        context: ProviderContext,
        store: SharedRuntimeStore
    ) -> TurnConfigPayload {
        var config = store.loadTurnConfig(type: context.selectedTurnType)
        if config.peer.isEmpty, let hysteria = store.loadHysteriaConfig(id: context.selectedServerId) {
            config.peer = hysteria.server
        }
        return config
    }

    private func startTurn(
        store: SharedRuntimeStore,
        turnConfig: TurnConfigPayload,
        hysteriaConfig: HysteriaConfigPayload
    ) throws -> Process {
        let executableURL = try bundleExecutable(named: "libvkturn")
        var arguments = [
            "-cache-dir", store.paths.directoryURL.path,
            "-peer", hysteriaConfig.server,
        ]

        if !turnConfig.link.isEmpty {
            arguments.append(turnConfig.link.localizedCaseInsensitiveContains("yandex") ? "-yandex-link" : "-vk-link")
            arguments.append(turnConfig.link)
        } else if !turnConfig.user.isEmpty && !turnConfig.pass.isEmpty {
            arguments.append(contentsOf: [
                "-turn-server", turnConfig.peer.isEmpty ? "turn:relay.turnbox.org:3478" : turnConfig.peer,
                "-turn-user", turnConfig.user,
                "-turn-pass", turnConfig.pass,
            ])
        }

        arguments.append(contentsOf: [
            "-listen", turnConfig.listen,
            "-n", "\(turnConfig.threads)",
        ])
        if turnConfig.udp { arguments.append("-udp") }
        if turnConfig.noDtls { arguments.append("-no-dtls") }

        let running = try Self.makeStreamingProcess(
            executableURL: executableURL,
            arguments: arguments
        )
        attachLogging(to: running, prefix: "TURN")
        appendLog("TURN process started")
        return running.process
    }

    private func writeRuntimeHysteriaConfig(
        store: SharedRuntimeStore,
        turnConfig: TurnConfigPayload,
        hysteriaConfig: HysteriaConfigPayload
    ) throws -> URL {
        let effectiveServer = turnConfig.enabled ? turnConfig.listen : hysteriaConfig.server
        let sni = hysteriaConfig.sni.isEmpty
            ? (hysteriaConfig.server.split(separator: ":").first.map(String.init) ?? "")
            : hysteriaConfig.sni

        let yaml = """
        server: \(effectiveServer)
        auth: \(hysteriaConfig.password)
        tls:
          sni: \(sni)
          insecure: \(hysteriaConfig.insecure ? "true" : "false")
        socks5:
          listen: 127.0.0.1:1080
        http:
          listen: 127.0.0.1:1081
        quic:
          handshakeTimeout: 10s
        """

        let configURL = store.paths.directoryURL.appendingPathComponent("runtime-hysteria-\(UUID().uuidString).yaml")
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    }

    private func startHysteria(
        store: SharedRuntimeStore,
        configURL: URL
    ) throws -> Process {
        let executableURL = try bundleExecutable(named: "libhysteria")
        let running = try Self.makeStreamingProcess(
            executableURL: executableURL,
            arguments: ["-c", configURL.path]
        )

        attachLogging(to: running, prefix: "HY2") { [weak self] line in
            guard let self else { return }
            if line.contains("SOCKS5 server listening") || line.contains("HTTP proxy server listening") {
                self.isHysteriaSocksReady = true
            }
            if line.localizedCaseInsensitiveContains("connected") {
                self.appendLog("Hysteria connected upstream")
            }
        }

        appendLog("Hysteria process started")
        return running.process
    }

    private func waitForHysteriaReady() async throws {
        isHysteriaSocksReady = false
        var waited: UInt64 = 0

        while waited < 25_000_000_000 {
            if isHysteriaSocksReady {
                appendLog("SOCKS5 listener is ready")
                return
            }

            if hysteriaProcess?.isRunning == false {
                throw CocoaError(.executableLoad)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 500_000_000
        }

        throw NSError(
            domain: "PacketTunnelProvider",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Hysteria SOCKS5 listener"]
        )
    }

    private func applyNetworkSettings(remoteAddress: String) async throws {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        settings.mtu = 1250

        let ipv4 = NEIPv4Settings(
            addresses: ["10.0.88.88"],
            subnetMasks: ["255.255.0.0"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1"])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setTunnelNetworkSettings(settings) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func startTun2Socks(store: SharedRuntimeStore) throws -> Process {
        let executableURL = try bundleExecutable(named: "tun2socks")
        let arguments = [
            "--socks-server-addr", "127.0.0.1:1080",
            "--netif-ipaddr", "10.0.88.88",
            "--netif-netmask", "255.255.0.0",
            "--tunmtu", "1250",
            "--loglevel", "info",
        ]

        let running = try Self.makeStreamingProcess(
            executableURL: executableURL,
            arguments: arguments
        )
        attachLogging(to: running, prefix: "T2S")
        appendLog("tun2socks process started")
        return running.process
    }

    private func attachLogging(
        to running: StreamingProcess,
        prefix: String,
        onLine: ((String) -> Void)? = nil
    ) {
        let task = Task { [weak self] in
            for await line in running.lines {
                self?.appendLog("[\(prefix)] \(line)")
                onLine?(line)
            }
        }
        loggingTasks.append(task)
    }

    private func writeStatus(
        state: PacketTunnelConnectionState,
        isConnected: Bool,
        connectedServerIP: String?,
        selectedServerId: String?,
        lastError: String?
    ) {
        runtimeStore?.writeStatus(
            PacketTunnelStatusSnapshot(
                state: state,
                isConnected: isConnected,
                connectedServerIP: connectedServerIP,
                selectedServerId: selectedServerId,
                lastError: lastError,
                updatedAt: Date()
            )
        )
    }

    private func appendLog(_ message: String) {
        runtimeStore?.appendLog(message)
    }

    private func bundleExecutable(named name: String) throws -> URL {
        if let url = Bundle.main.resourceExecutableURL(named: name) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func cleanupProcesses() {
        loggingTasks.forEach { $0.cancel() }
        loggingTasks.removeAll()

        turnProcess?.terminateIfRunning()
        turnProcess = nil

        hysteriaProcess?.terminateIfRunning()
        hysteriaProcess = nil

        tun2SocksProcess?.terminateIfRunning()
        tun2SocksProcess = nil
    }

    private static func makeStreamingProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> StreamingProcess {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let lines = AsyncStream<String> { continuation in
            var buffer = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    if !buffer.isEmpty {
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                    return
                }

                buffer.append(data)
                while let lineBreak = buffer.firstRange(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex ..< lineBreak.lowerBound)
                    buffer.removeSubrange(buffer.startIndex ... lineBreak.lowerBound)
                    let line = String(decoding: lineData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        continuation.yield(line)
                    }
                }
            }

            continuation.onTermination = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        try process.run()
        return StreamingProcess(process: process, lines: lines)
    }
}

private struct ProviderContext {
    let appGroupId: String
    let selectedServerId: String
    let selectedTurnType: String
}

private struct StreamingProcess {
    let process: Process
    let lines: AsyncStream<String>
}

private extension Process {
    func terminateIfRunning() {
        if isRunning {
            terminate()
        }
    }
}
