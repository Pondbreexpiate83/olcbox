# macOS VPN Client Implementation

This document describes the implemented macOS VPN client for the Turnbox KMP project.

## Created Files

### Main Application (`macosApp/`)
- **TurnboxApp.swift** - Main app entry point with Menu Bar Extra
- **MacosVpnManager.swift** - Core VPN manager with NetworkExtension integration
- **ContentView.swift** - Main SwiftUI interface with Dashboard, Settings, and Logs
- **MenuBarExtra.swift** - Menu bar icon and compact popup menu
- **Info.plist** - Application metadata and permissions
- **macosApp.entitlements** - Sandboxing and entitlements (App Group, Network Extension)
- **Resources/Assets.xcassets/** - Asset catalog for icons

### Packet Tunnel Extension (`PacketTunnelExtension/`)
- **PacketTunnelProvider.swift** - NEPacketTunnelProvider implementation
- **Info.plist** - Extension metadata
- **PacketTunnelExtension.entitlements** - Extension entitlements

## Architecture

### VPN Flow
```
User Action → MacosVpnManager → NETunnelProviderManager → PacketTunnelProvider
                                      ↓
                             App Group (Shared Configs)
                                      ↓
                          libvkturn → libhysteria → tun2socks
                                      ↓
                            System Network Stack
```

### Key Components

1. **MacosVpnManager** (`ObservableObject`)
   - Manages VPN connection lifecycle
   - Provides SwiftUI bindings via `@Published` properties
   - Handles `startVpn()` / `stopVpn()`
   - Implements `ping()` and `checkConnection()` using native binaries
   - Integrates with KMP via `MacosConfigStore`

2. **SwiftUI Interface**
   - **Dashboard**: Connection toggle, status pill, ping widget
   - **Settings**: Server configuration, TURN proxy settings
   - **Logs**: Real-time logs with auto-scroll and copy/clear
   - **Menu Bar Extra**: Quick connect/disconnect, server selection

3. **PacketTunnelProvider**
   - Runs in separate XPC process
   - Executes proxy chain: `libvkturn → libhysteria → tun2socks`
   - Configures TUN interface (10.0.88.88/16, DNS: 1.1.1.1)

### KMP Integration

The macOS client reuses existing KMP components:

```kotlin
// Already implemented:
- MacosHysteriaConfigDataSource (saves configs to App Group)
- MacosConfigStore (StateFlow for SwiftUI)
- HysteriaConfig & TurnConfig models
- Build targets: macosX64, macosArm64
```

Swift accesses KMP via:
- `MacosDependencies()` → `configStore` (for configs)
- `SharedUI.framework` (from KMP build)

### Native Binaries

Required binaries (place in `macosApp/Resources/`):
- `libvkturn` - TURN/VK/Yandex proxy
- `libhysteria` - Hysteria2 proxy
- `tun2socks` - TUN to SOCKS5 bridge

These are loaded at runtime from the app bundle.

## Features Implemented

### UI Features
- ✅ Modern macOS SwiftUI design
- ✅ NavigationSplitView (sidebar + content)
- ✅ Dashboard with status pill and ping
- ✅ Settings forms for server/TURN config
- ✅ Logs view with auto-scroll
- ✅ Menu Bar Extra (status bar icon)
- ✅ Light/Dark theme support
- ✅ SF Symbols integration

### VPN Features
- ✅ NetworkExtension integration
- ✅ Packet Tunnel Provider
- ✅ Start/stop VPN
- ✅ Status monitoring
- ✅ Proxy chaining (TURN → Hysteria)
- ✅ ping via libvkturn
- ✅ checkConnection with full chain
- ✅ UserNotifications for events

### Technical Features
- ✅ App Group for config sharing
- ✅ Process lifecycle management
- ✅ Timeout handling
- ✅ Error handling and logging
- ✅ Concurrent task management
- ✅ Temporary file cleanup

## Next Steps

### 1. Xcode Project Setup

Create targets in `iosApp.xcodeproj`:
- `Turnbox-macOS` (app) - Bundle ID: `org.turnbox.app.macos`
- `PacketTunnelExtension` - Bundle ID: `org.turnbox.app.macos.PacketTunnel`
- Shared App Group: `group.org.turnbox.app.shared`

### 2. Add Framework Dependency

In Xcode, add `SharedUI.framework` to both targets:
- Build location: `sharedUI/build/bin/macosArm64/debugFramework` (debug)
- Alternative: `sharedUI/build/bin/macosArm64/releaseFramework` (release)

### 3. Copy Native Binaries

Add to `macosApp/Resources/`:
```bash
cp /path/to/libvkturn /Users/.../macosApp/Resources/
cp /path/to/libhysteria /Users/.../macosApp/Resources/
cp /path/to/tun2socks /Users/.../macosApp/Resources/
```

Ensure binaries are:
- Code-signed with same identity as app
- Marked as "Copy Bundle Resources" in Xcode
- Have correct architecture (x86_64/arm64 universal)

### 4. Request System Extension Authorization

App will prompt on first VPN connect for:
- Network Extension approval
- System Extension installation

### 5. Complete KMP Integration

Implement in SwiftUI views:
- Load/save configs via `MacosConfigStore`
- Populate server list from `configStore.state`
- Handle server selection and deletion

## Development Notes

### Building KMP for macOS
```bash
./gradlew :sharedUI:compileKotlinMacosArm64
./gradlew :sharedUI:compileKotlinMacosX64
```

### Device Compatibility
- Supports macOS 11.0+ (Big Sur)
- Apple Silicon (arm64) and Intel (x86_64)
- Automatic framework selection via Xcode

### Security Considerations
- Sandboxed app with minimal entitlements
- App Group isolates shared data
- NetworkExtension in separate process
- No sensitive data in logs
- Temporary configs auto-deleted

## Troubleshooting

### VPN fails to start
- Check Console.app for extension logs
- Verify binaries are code-signed
- Ensure App Group entitlements match

### Configs not loading
- Verify App Group container access
- Check `~/Library/Group Containers/group.org.turnbox.app.shared/`

### No network traffic
- Verify tunnel is established
- Check proxy chain: `libvkturn → libhysteria → tun2socks`
- Confirm network settings: 10.0.88.88/16

## Usage

Once built and installed:
1. Configure server in Settings
2. (Optional) Enable TURN and configure credentials/link
3. Click "Connect" on Dashboard or in Menu Bar
4. Monitor logs for connection progress
5. Check ping and connection status
