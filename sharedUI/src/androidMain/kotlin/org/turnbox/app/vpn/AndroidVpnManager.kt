package org.turnbox.app.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import org.turnbox.app.data.model.HysteriaConfig
import org.turnbox.app.data.model.TurnConfig
import us.leaf3stones.hy2droid.proxy.Hysteria2VpnService
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

class AndroidVpnManager(private val context: Context) : VpnManager {
    override val logs: StateFlow<List<String>> = Hysteria2VpnService.logs
    override val isConnected: StateFlow<Boolean> = Hysteria2VpnService.isConnected

    override fun needsPermission(): Boolean = VpnService.prepare(context) != null

    override fun startVpn() {
        val intent = Intent(context, Hysteria2VpnService::class.java).apply {
            action = Hysteria2VpnService.ACTION_START_VPN
        }
        context.startService(intent)
    }

    override fun stopVpn() {
        val intent = Intent(context, Hysteria2VpnService::class.java).apply {
            action = Hysteria2VpnService.ACTION_STOP_VPN
        }
        context.startService(intent)
    }

    override suspend fun ping(turnConfig: TurnConfig, hysteriaConfig: HysteriaConfig): Long? =
        withContext(Dispatchers.IO) {
            val pingId = (0..999).random()
            val server = hysteriaConfig.server
            val randomPort = (30001..40000).random()
            
            val cmd = mutableListOf<String>().apply {
                add(File(context.applicationInfo.nativeLibraryDir, "libvkturn.so").absolutePath)
                add("-peer"); add(server)
                if (turnConfig.enabled) {
                    if (turnConfig.link.isNotBlank()) {
                        add(if (turnConfig.link.contains("yandex")) "-yandex-link" else "-vk-link")
                        add(turnConfig.link)
                    } else if (turnConfig.user.isNotBlank() && turnConfig.pass.isNotBlank()) {
                        add("-turn-server"); add(turnConfig.peer.ifBlank { "turn:relay.turnbox.org:3478" })
                        add("-turn-user"); add(turnConfig.user)
                        add("-turn-pass"); add(turnConfig.pass)
                    }
                }
                add("-ping")
                add("-ping-count"); add("1")
                add("-ping-timeout"); add("3s")
                add("-listen"); add("127.0.0.1:$randomPort")
            }

            try {
                val process = ProcessBuilder(cmd).redirectErrorStream(true).start()
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                var line: String?
                var rtt: Long? = null

                while (reader.readLine().also { line = it } != null) {
                    val match = Regex("time=([\\d.]+)ms").find(line ?: "")
                    if (match != null) {
                        val rttStr = match.groupValues[1]
                        rtt = rttStr.toDoubleOrNull()?.toLong()
                    }
                }

                process.waitFor()
                return@withContext rtt
            } catch (e: Exception) {
                null
            }
        }

    override suspend fun checkConnection(turnConfig: TurnConfig, hysteriaConfig: HysteriaConfig): Long? =
        withContext(Dispatchers.IO) {
            val checkId = (0..999).random()
            val server = hysteriaConfig.server
            
            var turnProcess: Process? = null
            val hysteriaConfigPath = File(context.cacheDir, "temp_check_$checkId.yaml").absolutePath
            
            try {
                val turnListen = "127.0.0.1:${(10000..20000).random()}"
                if (turnConfig.enabled) {
                    val turnCmd = mutableListOf<String>().apply {
                        add(File(context.applicationInfo.nativeLibraryDir, "libvkturn.so").absolutePath)
                        add("-peer"); add(server)
                        if (turnConfig.link.isNotBlank()) {
                            add(if (turnConfig.link.contains("yandex")) "-yandex-link" else "-vk-link")
                            add(turnConfig.link)
                        }
                        add("-listen"); add(turnListen)
                        add("-n"); add("1")
                    }
                    turnProcess = ProcessBuilder(turnCmd).start()
                }

                val effectiveServer = if (turnConfig.enabled) turnListen else server
                val socksPort = (20001..30000).random()
                val configContent = """
                    server: $effectiveServer
                    auth: ${hysteriaConfig.password}
                    tls:
                      sni: ${hysteriaConfig.sni.ifBlank { server.substringBefore(":") }}
                      insecure: ${hysteriaConfig.insecure}
                    socks5:
                      listen: 127.0.0.1:$socksPort
                    quic:
                      handshakeTimeout: 3s
                """.trimIndent()
                File(hysteriaConfigPath).writeText(configContent)

                val hysteriaCmd = listOf(
                    File(context.applicationInfo.nativeLibraryDir, "libhysteria.so").absolutePath,
                    "-c", hysteriaConfigPath
                )
                
                val hysteriaProcess = ProcessBuilder(hysteriaCmd).redirectErrorStream(true).start()
                
                val startTime = System.currentTimeMillis()
                var connected = false
                var latency: Long? = null
                
                val reader = BufferedReader(InputStreamReader(hysteriaProcess.inputStream))
                
                val timeout = 4000L
                while (System.currentTimeMillis() - startTime < timeout) {
                    if (reader.ready()) {
                        val line = reader.readLine() ?: break
                        if (line.contains("connected")) {
                            connected = true
                            latency = System.currentTimeMillis() - startTime
                            break
                        }
                    } else {
                        Thread.sleep(100)
                    }
                }

                hysteriaProcess.destroy()
                turnProcess?.destroy()
                File(hysteriaConfigPath).delete()

                return@withContext if (connected) latency ?: 1L else null

            } catch (e: Exception) {
                turnProcess?.destroy()
                File(hysteriaConfigPath).delete()
                null
            }
        }
}
