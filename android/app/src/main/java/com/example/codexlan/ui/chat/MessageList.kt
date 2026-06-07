package com.example.codexlan.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.codexlan.domain.ChatLine
import com.example.codexlan.domain.ChatRole
import com.example.codexlan.ui.components.CodexGlassCard
import com.example.codexlan.ui.components.StatusPill
import com.example.codexlan.ui.theme.CodexAccent
import com.example.codexlan.ui.theme.CodexAccentSoft
import com.example.codexlan.ui.theme.CodexAssistantBubble
import com.example.codexlan.ui.theme.CodexBorder
import com.example.codexlan.ui.theme.CodexError
import com.example.codexlan.ui.theme.CodexGold
import com.example.codexlan.ui.theme.CodexMuted
import com.example.codexlan.ui.theme.CodexPanel
import com.example.codexlan.ui.theme.CodexTextSecondary
import com.example.codexlan.ui.theme.CodexUserBubble

@Composable
fun MessageList(
    messages: List<ChatLine>,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (messages.isEmpty()) {
            item {
                EmptyCodexCard()
            }
        }
        items(messages, key = { it.id }) { line ->
            MessageBubble(line)
        }
    }
}

@Composable
private fun EmptyCodexCard() {
    CodexGlassCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            StatusPill(text = "LOCAL · PRIVATE · PAIRED", accent = CodexGold)
            Text(
                text = "Ready for command",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.ExtraBold,
            )
            Text(
                "Send a prompt to Codex and watch your local agent stream back in real time. The host keeps command execution and approvals under your control.",
                color = CodexTextSecondary,
                style = MaterialTheme.typography.bodyMedium,
            )
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PromptSuggestion("Say exactly: PHONE_PROMPT_OK")
                PromptSuggestion("Summarize this project in 5 bullets")
                PromptSuggestion("Run a safe read-only inspection")
            }
        }
    }
}

@Composable
private fun PromptSuggestion(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(CodexPanel.copy(alpha = 0.65f), RoundedCornerShape(16.dp))
            .border(1.dp, CodexBorder.copy(alpha = 0.42f), RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        Text(text, color = CodexTextSecondary, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun MessageBubble(line: ChatLine) {
    val isUser = line.role == ChatRole.User
    val alignment = if (isUser) Alignment.CenterEnd else Alignment.CenterStart
    val accent = when (line.role) {
        ChatRole.User -> CodexAccent
        ChatRole.Assistant -> CodexAccentSoft
        ChatRole.System -> CodexGold
        ChatRole.Error -> CodexError
    }
    val label = when (line.role) {
        ChatRole.User -> "You"
        ChatRole.Assistant -> "Codex"
        ChatRole.System -> "System"
        ChatRole.Error -> "Error"
    }
    val background = when (line.role) {
        ChatRole.User -> listOf(CodexUserBubble.copy(alpha = 0.96f), CodexAccent.copy(alpha = 0.16f))
        ChatRole.Assistant -> listOf(CodexAssistantBubble.copy(alpha = 0.98f), CodexPanel.copy(alpha = 0.9f))
        ChatRole.System -> listOf(CodexPanel.copy(alpha = 0.78f), CodexGold.copy(alpha = 0.08f))
        ChatRole.Error -> listOf(CodexError.copy(alpha = 0.18f), CodexPanel.copy(alpha = 0.88f))
    }

    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = alignment,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(if (isUser) 0.86f else 0.96f)
                .background(Brush.linearGradient(background), RoundedCornerShape(24.dp))
                .border(1.dp, accent.copy(alpha = 0.28f), RoundedCornerShape(24.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    label,
                    color = accent,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                )
                line.stream?.let { stream ->
                    Text(
                        text = stream.uppercase(),
                        color = CodexMuted,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
            Text(
                text = line.text,
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = if (line.role == ChatRole.Error) 0.96f else 0.92f),
                fontFamily = if (line.stream == "stdout" || line.stream == "stderr") FontFamily.Monospace else FontFamily.Default,
            )
        }
    }
}
