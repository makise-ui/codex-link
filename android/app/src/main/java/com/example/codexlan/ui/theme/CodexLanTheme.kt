package com.example.codexlan.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight

val CodexBackground = Color(0xFF05070D)
val CodexBackgroundDeep = Color(0xFF090D18)
val CodexPanel = Color(0xFF101724)
val CodexPanelHigh = Color(0xFF172033)
val CodexGlass = Color(0xCC151D2E)
val CodexSurface = Color(0xFF151B23)
val CodexSurfaceElevated = Color(0xFF1F2937)
val CodexBorder = Color(0xFF334155)
val CodexBorderBright = Color(0xFF4B5F7C)
val CodexAccent = Color(0xFF10D7A7)
val CodexAccentSoft = Color(0xFF67E8F9)
val CodexViolet = Color(0xFF8B5CF6)
val CodexGold = Color(0xFFF4C95D)
val CodexTextPrimary = Color(0xFFF8FAFC)
val CodexTextSecondary = Color(0xFFA7B0C0)
val CodexMuted = Color(0xFF64748B)
val CodexError = Color(0xFFFF6B7A)
val CodexUserBubble = Color(0xFF063D36)
val CodexAssistantBubble = Color(0xFF121B2B)

private val CodexDarkScheme: ColorScheme = darkColorScheme(
    primary = CodexAccent,
    onPrimary = Color(0xFF031F1A),
    secondary = CodexAccentSoft,
    onSecondary = Color(0xFF042F3A),
    tertiary = CodexGold,
    onTertiary = Color(0xFF2E2105),
    background = CodexBackground,
    onBackground = CodexTextPrimary,
    surface = CodexPanel,
    onSurface = CodexTextPrimary,
    surfaceVariant = CodexPanelHigh,
    onSurfaceVariant = CodexTextSecondary,
    outline = CodexBorder,
    error = CodexError,
    onError = Color.Black,
)

private val CodexTypography = Typography().let { base ->
    base.copy(
        headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.ExtraBold),
        headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.Bold),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = base.labelLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}

@Composable
fun CodexLanTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = CodexDarkScheme,
        typography = CodexTypography,
        content = content,
    )
}
