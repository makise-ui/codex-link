package com.example.codexlan.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import com.example.codexlan.ui.theme.CodexAccent
import com.example.codexlan.ui.theme.CodexAccentSoft
import com.example.codexlan.ui.theme.CodexBorderBright
import com.example.codexlan.ui.theme.CodexGold
import com.example.codexlan.ui.theme.CodexPanel
import com.example.codexlan.ui.theme.CodexPanelHigh
import com.example.codexlan.ui.theme.CodexTextSecondary

@Composable
fun PromptInput(
    enabled: Boolean,
    busy: Boolean,
    onSend: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var prompt by remember { mutableStateOf("") }
    val hint = when {
        busy -> "Codex is working… cancel to interrupt"
        enabled -> "Private LAN session · message Codex"
        else -> "Pair with a host bridge to begin"
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                Brush.linearGradient(listOf(CodexPanelHigh.copy(alpha = 0.96f), CodexPanel.copy(alpha = 0.94f))),
                RoundedCornerShape(28.dp),
            )
            .border(1.dp, CodexBorderBright.copy(alpha = 0.5f), RoundedCornerShape(28.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = hint,
            color = if (busy) CodexGold else CodexTextSecondary,
            style = MaterialTheme.typography.labelMedium,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            OutlinedTextField(
                value = prompt,
                onValueChange = { prompt = it },
                enabled = enabled,
                modifier = Modifier.weight(1f),
                minLines = 1,
                maxLines = 5,
                shape = RoundedCornerShape(22.dp),
                placeholder = { Text("Message Codex…") },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = CodexAccent,
                    unfocusedBorderColor = CodexBorderBright.copy(alpha = 0.42f),
                    focusedTextColor = MaterialTheme.colorScheme.onSurface,
                    unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                    focusedContainerColor = CodexPanel.copy(alpha = 0.55f),
                    unfocusedContainerColor = CodexPanel.copy(alpha = 0.42f),
                    cursorColor = CodexAccent,
                ),
            )
            Button(
                enabled = enabled && prompt.isNotBlank(),
                onClick = {
                    val trimmed = prompt.trim()
                    prompt = ""
                    onSend(trimmed)
                },
                shape = RoundedCornerShape(20.dp),
                border = BorderStroke(1.dp, CodexAccentSoft.copy(alpha = 0.45f)),
                colors = ButtonDefaults.buttonColors(
                    containerColor = CodexAccent,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ),
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null)
                Text("Send")
            }
        }
    }
}
