import SwiftUI

@main
struct TurnboxMacosApp: App {
    @StateObject private var viewModel = MacosAppViewModel()

    var body: some Scene {
        WindowGroup("Turnbox") {
            MacosRootView(
                viewModel: viewModel,
                vpnManager: viewModel.vpnManager
            )
            .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 980, height: 640)

        MenuBarExtra("Turnbox", systemImage: "shield.fill") {
            MenuBarQuickControlsView(
                viewModel: viewModel,
                vpnManager: viewModel.vpnManager
            )
        }
        .menuBarExtraStyle(.window)
    }
}
