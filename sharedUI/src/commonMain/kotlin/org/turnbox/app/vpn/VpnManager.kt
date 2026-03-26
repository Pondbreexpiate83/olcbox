package org.turnbox.app.vpn

import kotlinx.coroutines.flow.StateFlow
import org.turnbox.app.data.model.HysteriaConfig
import org.turnbox.app.data.model.TurnConfig

interface VpnManager {
    val logs: StateFlow<List<String>>
    val isConnected: StateFlow<Boolean>
    fun needsPermission(): Boolean
    fun startVpn()
    fun stopVpn()
    suspend fun ping(turnConfig: TurnConfig, hysteriaConfig: HysteriaConfig): Long?
    suspend fun checkConnection(turnConfig: TurnConfig, hysteriaConfig: HysteriaConfig): Long?
}