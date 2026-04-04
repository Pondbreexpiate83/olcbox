package org.turnbox.app.macos

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.turnbox.app.data.model.HysteriaConfig
import org.turnbox.app.data.model.TurnConfig
import org.turnbox.app.data.repository.HysteriaConfigRepository

data class MacosSavedServer(
    val id: String,
    val title: String,
    val server: String
)

data class MacosConfigState(
    val availableServers: List<MacosSavedServer> = emptyList(),
    val selectedServerId: String = "",
    val selectedTurnType: String = "custom",
    val hysteriaConfig: HysteriaConfig = HysteriaConfig(),
    val turnConfig: TurnConfig = TurnConfig(),
    val isLoaded: Boolean = false
)

class MacosConfigStore(
    private val repository: HysteriaConfigRepository
) {
    private val _state = MutableStateFlow(MacosConfigState())
    val state: StateFlow<MacosConfigState> = _state.asStateFlow()

    suspend fun reload() {
        val selectedServerId = repository.getSelectedHysteriaId()
        val selectedTurnType = repository.getSelectedTurnType()
        val servers = repository
            .getAllHysteriaConfigs()
            .map { (id, config) ->
                MacosSavedServer(
                    id = id,
                    title = config.name.ifBlank { config.server.ifBlank { id } },
                    server = config.server
                )
            }
            .sortedBy { it.title.lowercase() }

        val hysteriaConfig = if (selectedServerId.isBlank()) {
            HysteriaConfig()
        } else {
            repository.loadHysteriaConfig(selectedServerId)
        }

        val turnConfig = repository.loadTurnConfig(selectedTurnType)

        _state.value = MacosConfigState(
            availableServers = servers,
            selectedServerId = selectedServerId,
            selectedTurnType = selectedTurnType,
            hysteriaConfig = hysteriaConfig,
            turnConfig = turnConfig,
            isLoaded = true
        )
    }

    suspend fun selectServer(id: String) {
        repository.setSelectedHysteriaId(id)
        reload()
    }

    suspend fun selectTurnType(type: String) {
        repository.setSelectedTurnType(type)
        reload()
    }

    fun updateHysteria(config: HysteriaConfig) {
        _state.update { it.copy(hysteriaConfig = config) }
    }

    fun updateTurn(config: TurnConfig) {
        _state.update { it.copy(turnConfig = config) }
    }

    suspend fun save() {
        val currentState = state.value
        val targetId = currentState.selectedServerId.ifBlank { buildServerId(currentState.hysteriaConfig) }

        if (repository.getSelectedHysteriaId() != targetId) {
            repository.setSelectedHysteriaId(targetId)
        }
        if (repository.getSelectedTurnType() != currentState.selectedTurnType) {
            repository.setSelectedTurnType(currentState.selectedTurnType)
        }

        repository.saveHysteriaConfig(currentState.hysteriaConfig, targetId)
        repository.saveTurnConfig(currentState.turnConfig, currentState.selectedTurnType)
        reload()
    }

    suspend fun deleteSelectedServer() {
        val selectedId = state.value.selectedServerId
        if (selectedId.isBlank()) return
        repository.deleteHysteriaConfig(selectedId)
        reload()
    }

    private fun buildServerId(config: HysteriaConfig): String {
        val base = config.name.ifBlank { config.server.ifBlank { "default" } }
        val cleaned = buildString {
            for (char in base) {
                if (char.isLetterOrDigit() || char == '_' || char == '-') {
                    append(char)
                } else if (char.isWhitespace()) {
                    append('_')
                }
            }
        }.trim('_')

        return cleaned.ifBlank { "default" }
    }
}
