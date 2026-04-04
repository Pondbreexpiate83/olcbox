import CoreFoundation
import Foundation

enum PacketTunnelConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed
}

struct PacketTunnelStatusSnapshot: Codable {
    var state: PacketTunnelConnectionState
    var isConnected: Bool
    var connectedServerIP: String?
    var selectedServerId: String?
    var lastError: String?
    var updatedAt: Date

    static let empty = PacketTunnelStatusSnapshot(
        state: .disconnected,
        isConnected: false,
        connectedServerIP: nil,
        selectedServerId: nil,
        lastError: nil,
        updatedAt: .distantPast
    )
}

struct HysteriaConfigPayload: Codable {
    var server: String = ""
    var name: String = ""
    var password: String = ""
    var sni: String = ""
    var insecure: Bool = true
}

struct TurnConfigPayload: Codable {
    var enabled: Bool = false
    var peer: String = ""
    var link: String = ""
    var user: String = ""
    var pass: String = ""
    var threads: Int = 8
    var udp: Bool = true
    var noDtls: Bool = false
    var listen: String = "127.0.0.1:9000"
}

enum TurnboxRuntimeDefaults {
    static let appGroupId = "group.org.turnbox.app.shared"
    static let packetTunnelBundleId = "org.turnbox.app.PacketTunnelExtension"
    static let localizedTunnelName = "Turnbox VPN"
    static let sharedFolderName = "Turnbox"
    static let statusDefaultsKey = "org.turnbox.app.packetTunnel.status"
    static let runtimeNotification = "org.turnbox.app.packetTunnel.runtimeChanged"
    static let logsFileName = "packet-tunnel.log"
    static let masterConfigFileName = "hysteria.yaml"
}

struct TurnboxSharedPaths {
    let containerURL: URL
    let directoryURL: URL
    let logsURL: URL
    let masterConfigURL: URL

    static func resolve(appGroupId: String) throws -> TurnboxSharedPaths {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directoryURL = containerURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(TurnboxRuntimeDefaults.sharedFolderName, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return TurnboxSharedPaths(
            containerURL: containerURL,
            directoryURL: directoryURL,
            logsURL: directoryURL.appendingPathComponent(TurnboxRuntimeDefaults.logsFileName),
            masterConfigURL: directoryURL.appendingPathComponent(TurnboxRuntimeDefaults.masterConfigFileName)
        )
    }
}

final class SharedRuntimeStore {
    let appGroupId: String
    let paths: TurnboxSharedPaths

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(appGroupId: String = TurnboxRuntimeDefaults.appGroupId) throws {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            throw CocoaError(.coderInvalidValue)
        }
        self.appGroupId = appGroupId
        self.defaults = defaults
        self.paths = try TurnboxSharedPaths.resolve(appGroupId: appGroupId)
    }

    func writeStatus(_ snapshot: PacketTunnelStatusSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: TurnboxRuntimeDefaults.statusDefaultsKey)
        defaults.synchronize()
        DarwinNotificationBridge.post(name: TurnboxRuntimeDefaults.runtimeNotification)
    }

    func readStatus() -> PacketTunnelStatusSnapshot {
        guard
            let data = defaults.data(forKey: TurnboxRuntimeDefaults.statusDefaultsKey),
            let snapshot = try? decoder.decode(PacketTunnelStatusSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    func readLogs() -> [String] {
        guard
            let data = try? Data(contentsOf: paths.logsURL),
            let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func appendLog(_ message: String) {
        var logs = readLogs()
        logs.append(message)
        logs = Array(logs.suffix(300))
        writeLogs(logs)
    }

    func clearLogs() {
        writeLogs([])
    }

    func loadHysteriaConfig(id: String) -> HysteriaConfigPayload? {
        guard !id.isEmpty else { return nil }
        let url = paths.directoryURL.appendingPathComponent("hysteria_settings_\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(HysteriaConfigPayload.self, from: data)
    }

    func loadTurnConfig(type: String) -> TurnConfigPayload {
        let url = paths.directoryURL.appendingPathComponent("turn_settings_\(type).json")
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? decoder.decode(TurnConfigPayload.self, from: data)
        else {
            return defaultTurnConfig(type: type)
        }
        return decoded
    }

    func hostDisplay(from server: String) -> String? {
        let host = server.split(separator: ":").first.map(String.init) ?? server
        return host.isEmpty ? nil : host
    }

    private func writeLogs(_ logs: [String]) {
        let content = logs.joined(separator: "\n")
        try? content.data(using: .utf8)?.write(to: paths.logsURL, options: .atomic)
        DarwinNotificationBridge.post(name: TurnboxRuntimeDefaults.runtimeNotification)
    }

    private func defaultTurnConfig(type: String) -> TurnConfigPayload {
        switch type {
        case "vk":
            return TurnConfigPayload(
                enabled: true,
                link: "https://vk.com/call/join/dQw4w9WgXcQ",
                threads: 8,
                udp: true
            )
        case "yandex":
            return TurnConfigPayload(
                enabled: true,
                link: "https://telemost.yandex.ru/j/12345678901234",
                threads: 8,
                udp: true
            )
        default:
            return TurnConfigPayload()
        }
    }
}

enum DarwinNotificationBridge {
    static func post(name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
}

extension Bundle {
    func resourceExecutableURL(named name: String) -> URL? {
        if let direct = url(forResource: name, withExtension: nil) {
            return direct
        }

        if let resourcesURL = resourceURL {
            let candidate = resourcesURL.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
