import AppKit
import Foundation
import NetworkExtension
import SharedUI
import UserNotifications

@MainActor
final class MacosVpnManager: ObservableObject {
    @Published private(set) var connectionState: PacketTunnelConnectionState = .disconnected
    @Published private(set) var logs: [String] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isCheckingConnection = false
    @Published private(set) var lastPing: Int64?
    @Published private(set) var connectedServerIP: String?
    @Published var selectedServerId: String = ""

    let appGroupId: String
    let sharedDirectoryPath: String
    let masterConfigPath: String

    private let providerBundleIdentifier: String
    private let runtimeStore: SharedRuntimeStore
    private var tunnelManager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var darwinObserver: DarwinNotificationObserver?

    init(
        appGroupId: String = TurnboxRuntimeDefaults.appGroupId,
        sharedDirectoryPath: String,
        masterConfigPath: String,
        providerBundleIdentifier: String = TurnboxRuntimeDefaults.packetTunnelBundleId
    ) {
        self.appGroupId = appGroupId
        self.sharedDirectoryPath = sharedDirectoryPath
        self.masterConfigPath = masterConfigPath
        self.providerBundleIdentifier = providerBundleIdentifier
        self.runtimeStore = (try? SharedRuntimeStore(appGroupId: appGroupId)) ?? {
            fatalError("Unable to initialize shared runtime store for \(appGroupId)")
        }()

        requestNotificationAuthorization()
        reloadRuntimeState()
        installObservers()

        Task {
            try? await prepareManager()
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        darwinObserver?.invalidate()
    }

    func prepareManager() async throws {
        let manager = try await ensureManager()
        tunnelManager = manager
        apply(status: manager.connection.status)
        reloadRuntimeState()
    }

    func startVpn(selectedServerId: String, selectedTurnType: String) async {
        self.selectedServerId = selectedServerId

        do {
            let manager = try await ensureManager()
            try await configure(
                manager: manager,
                selectedServerId: selectedServerId,
                selectedTurnType: selectedTurnType
            )
            try manager.connection.startVPNTunnel()
            connectionState = .connecting
        } catch {
            connectionState = .failed
            postNotification(
                title: "VPN Error",
                body: error.localizedDescription
            )
            reloadRuntimeState()
        }
    }

    func stopVpn() async {
        guard let manager = try? await ensureManager() else { return }
        manager.connection.stopVPNTunnel()
        connectionState = .disconnecting
    }

    func clearLogs() {
        runtimeStore.clearLogs()
        reloadRuntimeState()
    }

    func copyLogs() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logs.joined(separator: "\n"), forType: .string)
    }

    func ping(
        turnConfig: TurnConfig,
        hysteriaConfig: HysteriaConfig
    ) async -> Int64? {
        do {
            let executableURL = try bundleExecutable(named: "libvkturn")
            let args = Self.buildPingArguments(
                turnConfig: turnConfig,
                hysteriaConfig: hysteriaConfig
            )
            let running = try Self.makeStreamingProcess(
                executableURL: executableURL,
                arguments: args
            )
            defer { running.process.terminateIfRunning() }

            var rtt: Int64?
            for await line in running.lines {
                if let latency = Self.parsePingLatency(from: line) {
                    rtt = latency
                }
            }
            await Self.awaitExit(of: running.process)
            lastPing = rtt
            return rtt
        } catch {
            runtimeStore.appendLog("Ping error: \(error.localizedDescription)")
            return nil
        }
    }

    func checkConnection(
        turnConfig: TurnConfig,
        hysteriaConfig: HysteriaConfig
    ) async -> Int64? {
        isCheckingConnection = true
        defer { isCheckingConnection = false }

        let tempDirectory = FileManager.default.temporaryDirectory
        let checkId = UUID().uuidString
        let configURL = tempDirectory.appendingPathComponent("turnbox-check-\(checkId).yaml")
        var turnProcess: Process?

        do {
            let server = hysteriaConfig.server
            let turnListen = "127.0.0.1:\(Int.random(in: 10000 ... 20000))"
            let socksPort = Int.random(in: 20001 ... 30000)

            if turnConfig.enabled {
                let executableURL = try bundleExecutable(named: "libvkturn")
                let args = Self.buildCheckTurnArguments(
                    turnConfig: turnConfig,
                    hysteriaConfig: hysteriaConfig,
                    listenAddress: turnListen
                )
                turnProcess = try Self.launchDetachedProcess(
                    executableURL: executableURL,
                    arguments: args
                )
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            let effectiveServer = turnConfig.enabled ? turnListen : server
            let configText = """
            server: \(effectiveServer)
            auth: \(hysteriaConfig.password)
            tls:
              sni: \(hysteriaConfig.sni.isEmpty ? server.split(separator: ":").first.map(String.init) ?? "" : hysteriaConfig.sni)
              insecure: \(hysteriaConfig.insecure ? "true" : "false")
            socks5:
              listen: 127.0.0.1:\(socksPort)
            quic:
              handshakeTimeout: 3s
            """
            try configText.write(to: configURL, atomically: true, encoding: .utf8)

            let hysteriaURL = try bundleExecutable(named: "libhysteria")
            let running = try Self.makeStreamingProcess(
                executableURL: hysteriaURL,
                arguments: ["-c", configURL.path]
            )
            defer {
                running.process.terminateIfRunning()
                turnProcess?.terminateIfRunning()
                try? FileManager.default.removeItem(at: configURL)
            }

            let start = ContinuousClock.now
            let connectedTask = Task<Int64?, Never> {
                for await line in running.lines {
                    if line.localizedCaseInsensitiveContains("connected") {
                        let duration = start.duration(to: .now)
                        return Int64(duration.components.seconds * 1000)
                            + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
                    }
                }
                return nil
            }

            let timeoutTask = Task<Int64?, Never> {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return nil
            }

            let latency = await withTaskGroup(of: Int64?.self) { group in
                group.addTask { await connectedTask.value }
                group.addTask { await timeoutTask.value }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }

            await Self.awaitExit(of: running.process, timeoutNanoseconds: 500_000_000)
            return latency
        } catch {
            turnProcess?.terminateIfRunning()
            try? FileManager.default.removeItem(at: configURL)
            runtimeStore.appendLog("Connection check error: \(error.localizedDescription)")
            return nil
        }
    }

    private func installObservers() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(status: self.tunnelManager?.connection.status ?? .invalid)
                self.reloadRuntimeState()
            }
        }

        darwinObserver = DarwinNotificationObserver(
            name: TurnboxRuntimeDefaults.runtimeNotification
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadRuntimeState()
            }
        }
    }

    private func ensureManager() async throws -> NETunnelProviderManager {
        if let tunnelManager {
            return tunnelManager
        }

        let allManagers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = allManagers.first ?? NETunnelProviderManager()
        tunnelManager = manager
        return manager
    }

    private func configure(
        manager: NETunnelProviderManager,
        selectedServerId: String,
        selectedTurnType: String
    ) async throws {
        let providerProtocol = (manager.protocolConfiguration as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        providerProtocol.providerBundleIdentifier = providerBundleIdentifier
        providerProtocol.serverAddress = TurnboxRuntimeDefaults.localizedTunnelName
        providerProtocol.disconnectOnSleep = false
        providerProtocol.providerConfiguration = [
            "appGroupId": appGroupId,
            "sharedDirectoryPath": sharedDirectoryPath,
            "masterConfigPath": masterConfigPath,
            "selectedServerId": selectedServerId,
            "selectedTurnType": selectedTurnType,
        ]

        manager.protocolConfiguration = providerProtocol
        manager.localizedDescription = TurnboxRuntimeDefaults.localizedTunnelName
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    private func reloadRuntimeState() {
        let snapshot = runtimeStore.readStatus()
        logs = runtimeStore.readLogs()
        connectedServerIP = snapshot.connectedServerIP
        apply(snapshot: snapshot)
    }

    private func apply(snapshot: PacketTunnelStatusSnapshot) {
        connectionState = snapshot.state
        isConnected = snapshot.isConnected
        connectedServerIP = snapshot.connectedServerIP

        if let lastError = snapshot.lastError, !lastError.isEmpty, snapshot.state == .failed {
            postNotification(title: "VPN Error", body: lastError)
        } else if snapshot.state == .connected {
            postNotification(
                title: "VPN Connected",
                body: snapshot.connectedServerIP ?? "Tunnel established"
            )
        }
    }

    private func apply(status: NEVPNStatus) {
        switch status {
        case .connected:
            connectionState = .connected
            isConnected = true
        case .connecting, .reasserting:
            connectionState = .connecting
            isConnected = false
        case .disconnecting:
            connectionState = .disconnecting
            isConnected = false
        case .disconnected, .invalid:
            connectionState = .disconnected
            isConnected = false
        @unknown default:
            connectionState = .failed
            isConnected = false
        }
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func bundleExecutable(named name: String) throws -> URL {
        if let url = Bundle.main.resourceExecutableURL(named: name) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static func buildPingArguments(
        turnConfig: TurnConfig,
        hysteriaConfig: HysteriaConfig
    ) -> [String] {
        var args = ["-peer", hysteriaConfig.server]

        if turnConfig.enabled {
            if !turnConfig.link.isEmpty {
                args.append(turnConfig.link.localizedCaseInsensitiveContains("yandex") ? "-yandex-link" : "-vk-link")
                args.append(turnConfig.link)
            } else if !turnConfig.user.isEmpty && !turnConfig.pass.isEmpty {
                args.append(contentsOf: [
                    "-turn-server", turnConfig.peer.isEmpty ? "turn:relay.turnbox.org:3478" : turnConfig.peer,
                    "-turn-user", turnConfig.user,
                    "-turn-pass", turnConfig.pass,
                ])
            }
        }

        args.append(contentsOf: [
            "-ping",
            "-ping-count", "1",
            "-ping-timeout", "3s",
            "-listen", "127.0.0.1:\(Int.random(in: 30001 ... 40000))",
        ])
        return args
    }

    private static func buildCheckTurnArguments(
        turnConfig: TurnConfig,
        hysteriaConfig: HysteriaConfig,
        listenAddress: String
    ) -> [String] {
        var args = ["-peer", hysteriaConfig.server]
        if !turnConfig.link.isEmpty {
            args.append(turnConfig.link.localizedCaseInsensitiveContains("yandex") ? "-yandex-link" : "-vk-link")
            args.append(turnConfig.link)
        } else if !turnConfig.user.isEmpty && !turnConfig.pass.isEmpty {
            args.append(contentsOf: [
                "-turn-server", turnConfig.peer.isEmpty ? "turn:relay.turnbox.org:3478" : turnConfig.peer,
                "-turn-user", turnConfig.user,
                "-turn-pass", turnConfig.pass,
            ])
        }

        args.append(contentsOf: ["-listen", listenAddress, "-n", "1"])
        return args
    }

    private static func parsePingLatency(from line: String) -> Int64? {
        guard
            let regex = try? NSRegularExpression(pattern: "time=([\\d.]+)ms"),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return Double(line[range]).map { Int64($0) }
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

    private static func launchDetachedProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    private static func awaitExit(
        of process: Process,
        timeoutNanoseconds: UInt64? = nil
    ) async {
        guard process.isRunning else { return }

        let waitTask = Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }
        }

        if let timeoutNanoseconds {
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            _ = await withTaskGroup(of: Void.self) { group in
                group.addTask { await waitTask.value }
                group.addTask { await timeoutTask.value }
                await group.next()
                group.cancelAll()
            }
        } else {
            await waitTask.value
        }
    }
}

private struct StreamingProcess {
    let process: Process
    let lines: AsyncStream<String>
}

private final class DarwinNotificationObserver {
    private let name: String
    private let callback: () -> Void
    private let observer: UnsafeRawPointer

    init(name: String, callback: @escaping () -> Void) {
        self.name = name
        self.callback = callback
        self.observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let instance = Unmanaged<DarwinNotificationObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                instance.callback()
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    func invalidate() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            CFNotificationName(name as CFString),
            nil
        )
    }
}

private extension Process {
    func terminateIfRunning() {
        if isRunning {
            terminate()
        }
    }
}

private extension NETunnelProviderManager {
    static func loadAllFromPreferences() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    func saveToPreferences() async throws {
        try await withCheckedThrowingContinuation { continuation in
            saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func loadFromPreferences() async throws {
        try await withCheckedThrowingContinuation { continuation in
            loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
