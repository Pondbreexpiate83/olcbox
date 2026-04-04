package org.turnbox.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily
import multiplatform_app.sharedui.generated.resources.Res
import multiplatform_app.sharedui.generated.resources.google_sans
import org.jetbrains.compose.resources.Font

@Composable
fun getAppTypography(): Typography {
    val googleSans = FontFamily(
        Font(Res.font.google_sans)
    )

    val defaultTypography = Typography()

    return Typography(
        displayLarge = defaultTypography.displayLarge.copy(fontFamily = googleSans),
        displayMedium = defaultTypography.displayMedium.copy(fontFamily = googleSans),
        displaySmall = defaultTypography.displaySmall.copy(fontFamily = googleSans),
        headlineLarge = defaultTypography.headlineLarge.copy(fontFamily = googleSans),
        headlineMedium = defaultTypography.headlineMedium.copy(fontFamily = googleSans),
        headlineSmall = defaultTypography.headlineSmall.copy(fontFamily = googleSans),
        titleLarge = defaultTypography.titleLarge.copy(fontFamily = googleSans),
        titleMedium = defaultTypography.titleMedium.copy(fontFamily = googleSans),
        titleSmall = defaultTypography.titleSmall.copy(fontFamily = googleSans),
        bodyLarge = defaultTypography.bodyLarge.copy(fontFamily = googleSans),
        bodyMedium = defaultTypography.bodyMedium.copy(fontFamily = googleSans),
        bodySmall = defaultTypography.bodySmall.copy(fontFamily = googleSans),
        labelLarge = defaultTypography.labelLarge.copy(fontFamily = googleSans),
        labelMedium = defaultTypography.labelMedium.copy(fontFamily = googleSans),
        labelSmall = defaultTypography.labelSmall.copy(fontFamily = googleSans)
    )
}