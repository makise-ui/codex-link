package com.example.codexlan.ui.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.codexlan.domain.ConnectionState
import com.example.codexlan.ui.components.CodexGlassCard
import com.example.codexlan.ui.components.StatusPill
import com.example.codexlan.ui.theme.CodexAccent
import com.example.codexlan.ui.theme.CodexAccentSoft
import com.example.codexlan.ui.theme.CodexError
import com.example.codexlan.ui.theme.CodexGold
import com.example.codexlan.ui.theme.CodexMuted
import com.example.codexlan.ui.theme.CodexTextSecondary

@Composable
fun RunStatusBar(
    connectionState: ConnectionState,
    statusText: String,
    activeRunId: String?,
    modifier: Modifier = Modifier,
) {
    val isRunning = activeRunId != null
    val accent = when {
        connectionState == ConnectionState.Failed -> CodexError
        isRunning -> CodexGold
        connectionState == ConnectionState.Authenticated -> CodexAccent
        else -> CodexMuted
    }

    CodexGlassCard(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        text = if (isRunning) "Agent in motion" else "Bridge status",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = statusText.ifBlank { connectionState.name },
                        color = CodexTextSecondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                StatusPill(
                    text = if (isRunning) "Running" else connectionState.name,
                    accent = accent,
                )
            }

            if (isRunning) {
                LinearProgressIndicator(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 2.dp),
                    color = CodexGold,
                    trackColor = CodexAccentSoft.copy(alpha = 0.12f),
                )
                Text(
                    text = "run ${activeRunId?.take(8)} · streaming from local Codex",
                    color = CodexTextSecondary,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}
