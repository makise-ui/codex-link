package com.example.codexlan.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.codexlan.ui.theme.CodexAccent
import com.example.codexlan.ui.theme.CodexBackground
import com.example.codexlan.ui.theme.CodexBackgroundDeep
import com.example.codexlan.ui.theme.CodexBorder
import com.example.codexlan.ui.theme.CodexGlass
import com.example.codexlan.ui.theme.CodexGold
import com.example.codexlan.ui.theme.CodexPanel
import com.example.codexlan.ui.theme.CodexPanelHigh
import com.example.codexlan.ui.theme.CodexTextSecondary
import com.example.codexlan.ui.theme.CodexViolet

@Composable
fun CodexBackdrop(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        CodexBackgroundDeep,
                        CodexBackground,
                        Color(0xFF03040A),
                    ),
                ),
            ),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(CodexViolet.copy(alpha = 0.28f), Color.Transparent),
                        center = Offset(120f, 80f),
                        radius = 520f,
                    ),
                ),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(CodexAccent.copy(alpha = 0.18f), Color.Transparent),
                        center = Offset(900f, 1250f),
                        radius = 700f,
                    ),
                ),
        )
        content()
    }
}

@Composable
fun CodexGlassCard(
    modifier: Modifier = Modifier,
    shape: RoundedCornerShape = RoundedCornerShape(28.dp),
    borderColor: Color = CodexBorder.copy(alpha = 0.62f),
    content: @Composable () -> Unit,
) {
    Column(
        modifier = modifier
            .background(
                Brush.linearGradient(
                    listOf(
                        CodexGlass.copy(alpha = 0.94f),
                        CodexPanel.copy(alpha = 0.92f),
                        CodexPanelHigh.copy(alpha = 0.82f),
                    ),
                ),
                shape,
            )
            .border(1.dp, borderColor, shape)
            .padding(18.dp),
    ) {
        content()
    }
}

@Composable
fun StatusPill(
    text: String,
    modifier: Modifier = Modifier,
    accent: Color = CodexAccent,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(999.dp),
        color = accent.copy(alpha = 0.13f),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.38f)),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Box(
                modifier = Modifier
                    .background(accent, RoundedCornerShape(999.dp))
                    .padding(3.dp),
            )
            Text(
                text = text,
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
            )
            trailing?.invoke(this)
        }
    }
}

@Composable
fun SectionEyebrow(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = CodexGold,
) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        color = color,
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
    )
}

@Composable
fun MutedText(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        modifier = modifier,
        color = CodexTextSecondary,
        style = MaterialTheme.typography.bodyMedium,
    )
}
