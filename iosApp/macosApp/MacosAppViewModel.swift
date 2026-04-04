import Foundation
import SharedUI

struct MacosServerOption: Identifiable, Equatable {
    let id: String
    let title: String
    let server: String
}

struct MacosEditableConfigState {
    var availableServers: [MacosServerOption] = []
    var selectedServerId: String = ""
    var selectedTurnType: String = "custom"
    var hysteriaConfig = HysteriaConfig()
    var turnConfig = TurnConfig()
    var isLoaded = false
}

@MainActor
final class MacosAppViewModel: ObservableObject {
    @Published private(set) var configState = MacosEditableConfigState()
    @Published private(set) var lastConnectionCheck: Int64?

    let vpnManager: MacosVpnManager

    private let dependencies: MacosDependencies
    private let configStore: MacosConfigStore
    private let flowBridge = StateFlowBridge()
    private var configSubscription: FlowSubscription?
    private var pingRefreshTask: Task<Void, Never>?

    init(appGroupId: String = TurnboxRuntimeDefaults.appGroupId) {
        self.dependencies = MacosDependencies(appGroupId: appGroupId)
        self.configStore = dependencies.configStore
        self.vpnManager = MacosVpnManager(
            appGroupId: dependencies.appGroupIdentifier,
            sharedDirectoryPath: dependencies.sharedDirectoryPath,
            masterConfigPath: dependencies.masterConfigPath
        )

        observeConfigState()

        Task {
            try? await reload()
        }
    }

    deinit {
        configSubscription?.cancel()
        flowBridge.close()
        pingRefreshTask?.cancel()
    }

    func reload() async throws {
        try await configStore.reloadAsync()
    }

    func save() async throws {
        try await configStore.saveAsync()
    }

    func selectServer(_ id: String) {
        Task {
            try? await configStore.selectServerAsync(id: id)
        }
    }

    func selectTurnType(_ type: String) {
        Task {
            try? await configStore.selectTurnTypeAsync(type: type)
        }
    }

    func deleteSelectedServer() {
        Task {
            try? await configStore.deleteSelectedServerAsync()
        }
    }

    func updateHysteria(
        server: String? = nil,
        name: String? = nil,
        password: String? = nil,
        sni: String? = nil,
        insecure: Bool? = nil
    ) {
        let current = configState.hysteriaConfig
        let updated = HysteriaConfig(
            server: server ?? current.server,
            name: name ?? current.name,
            password: password ?? current.password,
            sni: sni ?? current.sni,
            insecure: insecure ?? current.insecure
        )
        configStore.updateHysteria(config: updated)
        configState.hysteriaConfig = updated
    }

    func updateTurn(
        enabled: Bool? = nil,
        peer: String? = nil,
        link: String? = nil,
        user: String? = nil,
        pass: String? = nil,
        threads: Int? = nil,
        udp: Bool? = nil,
        noDtls: Bool? = nil,
        listen: String? = nil
    ) {
        let current = configState.turnConfig
        let updated = TurnConfig(
            enabled: enabled ?? current.enabled,
            peer: peer ?? current.peer,
            link: link ?? current.link,
            user: user ?? current.user,
            pass: pass ?? current.pass,
            threads: Int32(threads ?? Int(current.threads)),
            udp: udp ?? current.udp,
            noDtls: noDtls ?? current.noDtls,
            listen: listen ?? current.listen
        )
        configStore.updateTurn(config: updated)
        configState.turnConfig = updated
    }

    func toggleVpn() {
        Task {
            if vpnManager.isConnected {
                await vpnManager.stopVpn()
            } else {
                try? await save()
                await vpnManager.startVpn(
                    selectedServerId: configState.selectedServerId,
                    selectedTurnType: configState.selectedTurnType
                )
            }
        }
    }

    func refreshPing() {
        Task {
            _ = await vpnManager.ping(
                turnConfig: configState.turnConfig,
                hysteriaConfig: configState.hysteriaConfig
            )
        }
    }

    func runConnectionCheck() {
        Task {
            lastConnectionCheck = await vpnManager.checkConnection(
                turnConfig: configState.turnConfig,
                hysteriaConfig: configState.hysteriaConfig
            )
        }
    }

    func startDashboardPingRefresh() {
        pingRefreshTask?.cancel()
        pingRefreshTask = Task { [weak self] in
            guard let self else { return }

            if self.vpnManager.isConnected {
                _ = await self.vpnManager.ping(
                    turnConfig: self.configState.turnConfig,
                    hysteriaConfig: self.configState.hysteriaConfig
                )
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard self.vpnManager.isConnected else { continue }
                _ = await self.vpnManager.ping(
                    turnConfig: self.configState.turnConfig,
                    hysteriaConfig: self.configState.hysteriaConfig
                )
            }
        }
    }

    func stopDashboardPingRefresh() {
        pingRefreshTask?.cancel()
        pingRefreshTask = nil
    }

    func clearLogs() {
        vpnManager.clearLogs()
    }

    func copyLogs() {
        vpnManager.copyLogs()
    }

    private func observeConfigState() {
        configSubscription = flowBridge.watchConfigState(
            flow: configStore.state
        ) { [weak self] state in
            Task { @MainActor [weak self] in
                self?.apply(configState: state)
            }
        }
    }

    private func apply(configState state: MacosConfigState) {
        let serversArray = (state.availableServers as? [MacosSavedServer])
            ?? ((state.availableServers as? NSArray)?.compactMap { $0 as? MacosSavedServer } ?? [])

        let servers = serversArray.map {
            MacosServerOption(id: $0.id, title: $0.title, server: $0.server)
        }

        configState = MacosEditableConfigState(
            availableServers: servers,
            selectedServerId: state.selectedServerId,
            selectedTurnType: state.selectedTurnType,
            hysteriaConfig: state.hysteriaConfig,
            turnConfig: state.turnConfig,
            isLoaded: state.isLoaded
        )
        vpnManager.selectedServerId = state.selectedServerId
    }
}

private extension MacosConfigStore {
    func reloadAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            reload { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func saveAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            save { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func selectServerAsync(id: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            selectServer(id: id) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func selectTurnTypeAsync(type: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            selectTurnType(type: type) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func deleteSelectedServerAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            deleteSelectedServer { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
