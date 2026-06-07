package com.example.codexlan.ui.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.codexlan.domain.ChatLine
import com.example.codexlan.domain.ConnectionState
import com.example.codexlan.ui.components.CodexBackdrop
import com.example.codexlan.ui.components.CodexGlassCard
import com.example.codexlan.ui.components.SectionEyebrow
import com.example.codexlan.ui.components.StatusPill
import com.example.codexlan.ui.theme.CodexAccent
import com.example.codexlan.ui.theme.CodexGold
import com.example.codexlan.ui.theme.CodexTextSecondary
import com.example.codexlan.ui.theme.CodexViolet

@Composable
fun ChatScreen(
    connectionState: ConnectionState,
    statusText: String,
    sessionId: String?,
    activeRunId: String?,
    messages: List<ChatLine>,
    onSendPrompt: (String) -> Unit,
    onCancel: () -> Unit,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val busy = activeRunId != null
    CodexBackdrop(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ChatHeroHeader(
                connectionState = connectionState,
                sessionId = sessionId,
                activeRunId = activeRunId,
            )

            RunStatusBar(
                connectionState = connectionState,
                statusText = statusText,
                activeRunId = activeRunId,
            )

            MessageList(
                messages = messages,
                modifier = Modifier.weight(1f),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDisconnect) {
                    Text("Disconnect", color = CodexTextSecondary)
                }
                OutlinedButton(
                    enabled = busy,
                    onClick = onCancel,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = CodexGold),
                ) {
                    Text("Cancel active run")
                }
            }

            PromptInput(
                enabled = connectionState == ConnectionState.Authenticated && !busy && sessionId != null,
                busy = busy,
                onSend = onSendPrompt,
            )
        }
    }
}

@Composable
private fun ChatHeroHeader(
    connectionState: ConnectionState,
    sessionId: String?,
    activeRunId: String?,
) {
    CodexGlassCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.weight(1f)) {
                    SectionEyebrow("Private local agent")
                    Text(
                        "Codex LAN",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.ExtraBold,
                    )
                    Text(
                        "A premium command deck for your local Codex session.",
                        color = CodexTextSecondary,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                StatusPill(text = connectionState.name, accent = if (connectionState == ConnectionState.Authenticated) CodexAccent else CodexViolet)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatusPill(
                    text = "session ${sessionId?.take(8) ?: "pending"}",
                    accent = CodexAccent,
                )
                StatusPill(
                    text = activeRunId?.let { "run ${it.take(8)}" } ?: "idle",
                    accent = if (activeRunId == null) CodexViolet else CodexGold,
                )
            }
        }
    }
}
