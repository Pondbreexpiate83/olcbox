package org.turnbox.app.ui.theme

import androidx.compose.runtime.*

// CompositionLocal для ручного переключения темы (доступен на всех платформах)
internal val LocalThemeIsDark = compositionLocalOf { mutableStateOf(true) }

@Composable
expect fun AppTheme(
    content: @Composable () -> Unit
)
