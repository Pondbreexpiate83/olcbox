package org.turnbox.app.macos

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class FlowSubscription internal constructor(
    private val job: Job
) {
    fun cancel() {
        job.cancel()
    }
}

class StateFlowBridge {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun watchConfigState(
        flow: StateFlow<MacosConfigState>,
        onEach: (MacosConfigState) -> Unit
    ): FlowSubscription {
        val job = scope.launch {
            flow.collect { onEach(it) }
        }
        return FlowSubscription(job)
    }

    fun watchBoolean(
        flow: StateFlow<Boolean>,
        onEach: (Boolean) -> Unit
    ): FlowSubscription {
        val job = scope.launch {
            flow.collect { onEach(it) }
        }
        return FlowSubscription(job)
    }

    fun watchStringList(
        flow: StateFlow<List<String>>,
        onEach: (List<String>) -> Unit
    ): FlowSubscription {
        val job = scope.launch {
            flow.collect { onEach(it) }
        }
        return FlowSubscription(job)
    }

    fun close() {
        scope.cancel()
    }
}
