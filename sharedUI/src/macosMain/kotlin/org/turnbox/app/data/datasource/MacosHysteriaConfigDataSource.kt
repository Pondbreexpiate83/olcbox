package org.turnbox.app.data.datasource

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.serialization.json.Json
import org.turnbox.app.data.MASTER_HYSTERIA_CONFIG_FILE_NAME
import org.turnbox.app.data.model.HysteriaConfig
import org.turnbox.app.data.model.TurnConfig
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.NSUserDefaults
import platform.Foundation.stringWithContentsOfFile
import platform.Foundation.writeToFile

const val DEFAULT_MACOS_APP_GROUP_ID = "group.org.turnbox.app.shared"

private const val KEY_SELECTED_TURN_TYPE = "selected_turn_type"
private const val KEY_SELECTED_HYSTERIA_ID = "selected_hysteria_id"
private const val TURNBOX_DIRECTORY = "Application Support/Turnbox"

@OptIn(ExperimentalForeignApi::class)
class MacosHysteriaConfigDataSource(
    val appGroupId: String = DEFAULT_MACOS_APP_GROUP_ID
) : HysteriaConfigDataSource {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val fileManager = NSFileManager.defaultManager
    private val defaults = requireNotNull(NSUserDefaults(suiteName = appGroupId)) {
        "Unable to create shared defaults for app group $appGroupId"
    }

    val sharedDirectoryPath: String by lazy {
        val rootPath = requireNotNull(
            fileManager
                .containerURLForSecurityApplicationGroupIdentifier(appGroupId)
                ?.path
        ) {
            "Unable to resolve shared container for app group $appGroupId"
        }
        val directoryPath = "$rootPath/$TURNBOX_DIRECTORY"
        fileManager.createDirectoryAtPath(
            path = directoryPath,
            withIntermediateDirectories = true,
            attributes = null,
            error = null
        )
        directoryPath
    }

    val masterConfigPath: String
        get() = "$sharedDirectoryPath/$MASTER_HYSTERIA_CONFIG_FILE_NAME"

    override suspend fun saveHysteriaConfig(config: HysteriaConfig, id: String) {
        writeText(
            path = "$sharedDirectoryPath/hysteria_settings_$id.json",
            text = json.encodeToString(HysteriaConfig.serializer(), config)
        )

        if (getSelectedHysteriaId() == id) {
            updateVpnConfigFile(config, loadTurnConfig(getSelectedTurnType()))
        }
    }

    override suspend fun loadHysteriaConfig(id: String): HysteriaConfig {
        if (id.isBlank()) return HysteriaConfig()
        val text = readText("$sharedDirectoryPath/hysteria_settings_$id.json") ?: return HysteriaConfig()
        return try {
            json.decodeFromString(HysteriaConfig.serializer(), text)
        } catch (_: Exception) {
            HysteriaConfig()
        }
    }

    override suspend fun saveTurnConfig(config: TurnConfig, type: String) {
        writeText(
            path = "$sharedDirectoryPath/turn_settings_$type.json",
            text = json.encodeToString(TurnConfig.serializer(), config)
        )

        if (getSelectedTurnType() == type) {
            updateVpnConfigFile(loadHysteriaConfig(getSelectedHysteriaId()), config)
        }
    }

    override suspend fun loadTurnConfig(type: String): TurnConfig {
        val path = "$sharedDirectoryPath/turn_settings_$type.json"
        val text = readText(path)
        if (text.isNullOrBlank()) return defaultTurnConfig(type)

        return try {
            json.decodeFromString(TurnConfig.serializer(), text)
        } catch (_: Exception) {
            defaultTurnConfig(type)
        }
    }

    override suspend fun saveRawConfig(text: String) {
        writeText(masterConfigPath, text)
    }

    override suspend fun getSelectedTurnType(): String {
        return defaults.stringForKey(KEY_SELECTED_TURN_TYPE) ?: "custom"
    }

    override suspend fun setSelectedTurnType(type: String) {
        defaults.setObject(type, forKey = KEY_SELECTED_TURN_TYPE)
        defaults.synchronize()
        updateVpnConfigFile(loadHysteriaConfig(getSelectedHysteriaId()), loadTurnConfig(type))
    }

    override suspend fun getSelectedHysteriaId(): String {
        return defaults.stringForKey(KEY_SELECTED_HYSTERIA_ID) ?: ""
    }

    override suspend fun setSelectedHysteriaId(id: String) {
        defaults.setObject(id, forKey = KEY_SELECTED_HYSTERIA_ID)
        defaults.synchronize()
        if (id.isNotBlank()) {
            updateVpnConfigFile(loadHysteriaConfig(id), loadTurnConfig(getSelectedTurnType()))
        }
    }

    override suspend fun getAllHysteriaConfigs(): List<Pair<String, HysteriaConfig>> {
        val items = fileManager.contentsOfDirectoryAtPath(sharedDirectoryPath, error = null) ?: return emptyList()
        return items
            .mapNotNull { item -> item as? String }
            .filter { it.startsWith("hysteria_settings_") && it.endsWith(".json") }
            .map { name ->
                val id = name.removePrefix("hysteria_settings_").removeSuffix(".json")
                id to loadHysteriaConfig(id)
            }
    }

    override suspend fun deleteHysteriaConfig(id: String) {
        val path = "$sharedDirectoryPath/hysteria_settings_$id.json"
        if (fileManager.fileExistsAtPath(path)) {
            fileManager.removeItemAtPath(path, error = null)
        }
        if (getSelectedHysteriaId() == id) {
            setSelectedHysteriaId("")
        }
    }

    private suspend fun updateVpnConfigFile(hysteria: HysteriaConfig, turn: TurnConfig) {
        writeText(masterConfigPath, hysteria.getFullConfig(turn))
    }

    private fun defaultTurnConfig(type: String): TurnConfig {
        return when (type) {
            "vk" -> TurnConfig(
                enabled = true,
                link = "https://vk.com/call/join/dQw4w9WgXcQ",
                threads = 8,
                udp = true
            )

            "yandex" -> TurnConfig(
                enabled = true,
                link = "https://telemost.yandex.ru/j/12345678901234",
                threads = 8,
                udp = true
            )

            else -> TurnConfig()
        }
    }

    private fun readText(path: String): String? {
        if (!fileManager.fileExistsAtPath(path)) return null
        return NSString.stringWithContentsOfFile(
            path = path,
            encoding = NSUTF8StringEncoding,
            error = null
        ) as String?
    }

    private fun writeText(path: String, text: String) {
        (text as NSString).writeToFile(
            path = path,
            atomically = true,
            encoding = NSUTF8StringEncoding,
            error = null
        )
    }
}
