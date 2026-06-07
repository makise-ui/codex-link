package com.example.codexlan.ui.pairing

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.codexlan.data.StoredBridgeCredentials
import com.example.codexlan.domain.ConnectionState
import com.example.codexlan.ui.components.CodexBackdrop
import com.example.codexlan.ui.components.CodexGlassCard
import com.example.codexlan.ui.components.SectionEyebrow
import com.example.codexlan.ui.components.StatusPill
import com.example.codexlan.ui.theme.CodexAccent
import com.example.codexlan.ui.theme.CodexAccentSoft
import com.example.codexlan.ui.theme.CodexBorder
import com.example.codexlan.ui.theme.CodexGold
import com.example.codexlan.ui.theme.CodexPanel
import com.example.codexlan.ui.theme.CodexPanelHigh
import com.example.codexlan.ui.theme.CodexTextSecondary
import com.example.codexlan.ui.theme.CodexViolet

@Composable
fun PairingScreen(
    connectionState: ConnectionState,
    statusText: String,
    savedCredentials: StoredBridgeCredentials?,
    onPair: (payload: String, deviceName: String) -> Unit,
    onReconnect: () -> Unit,
    onForgetSaved: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var payload by remember { mutableStateOf("") }
    var deviceName by remember { mutableStateOf("Android Codex Controller") }
    var showScanner by remember { mutableStateOf(false) }

    if (showScanner) {
        QrScannerScreen(
            onPayloadScanned = { scannedPayload ->
                payload = scannedPayload
                showScanner = false
                if (deviceName.isNotBlank()) {
                    onPair(scannedPayload, deviceName)
                }
            },
            onClose = { showScanner = false },
            modifier = modifier,
        )
        return
    }

    CodexBackdrop(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            CodexGlassCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    StatusPill(text = "LOCAL NETWORK ONLY", accent = CodexGold)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SectionEyebrow("Codex controller")
                        Text(
                            "Pair your private command deck",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.ExtraBold,
                        )
                        Text(
                            "Scan the QR printed by the host bridge. Your phone gets a one-time local token and talks only to the machine on your LAN.",
                            color = CodexTextSecondary,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    Button(
                        enabled = connectionState != ConnectionState.Connecting,
                        onClick = { showScanner = true },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(20.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = CodexAccent),
                    ) {
                        Text("Scan majestic QR", color = MaterialTheme.colorScheme.onPrimary)
                    }
                }
            }

            CodexGlassCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Manual pairing", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        StatusPill(text = connectionState.name, accent = if (connectionState == ConnectionState.Failed) CodexGold else CodexViolet)
                    }
                    OutlinedTextField(
                        value = deviceName,
                        onValueChange = { deviceName = it },
                        label = { Text("Device name") },
                        singleLine = true,
                        shape = RoundedCornerShape(18.dp),
                        colors = pairingTextFieldColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = payload,
                        onValueChange = { payload = it },
                        label = { Text("Pairing JSON") },
                        minLines = 5,
                        maxLines = 9,
                        shape = RoundedCornerShape(18.dp),
                        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        colors = pairingTextFieldColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        enabled = payload.isNotBlank() && deviceName.isNotBlank() && connectionState != ConnectionState.Connecting,
                        onClick = { onPair(payload, deviceName) },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(20.dp),
                    ) {
                        Text("Pair with host bridge")
                    }
                }
            }

            savedCredentials?.let { credentials ->
                CodexGlassCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionEyebrow("Saved host", color = CodexAccentSoft)
                        Text(credentials.url, color = CodexTextSecondary, fontFamily = FontFamily.Monospace)
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Button(onClick = onReconnect, enabled = connectionState != ConnectionState.Connecting) {
                                Text("Reconnect")
                            }
                            OutlinedButton(onClick = onForgetSaved) {
                                Text("Forget")
                            }
                        }
                    }
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Brush.linearGradient(listOf(CodexPanel.copy(alpha = 0.55f), CodexPanelHigh.copy(alpha = 0.35f))), RoundedCornerShape(20.dp))
                    .border(1.dp, CodexBorder.copy(alpha = 0.38f), RoundedCornerShape(20.dp))
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text("Status", color = CodexGold, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                Text(statusText, color = CodexTextSecondary, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun pairingTextFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = CodexAccent,
    unfocusedBorderColor = CodexBorder.copy(alpha = 0.5f),
    focusedContainerColor = CodexPanel.copy(alpha = 0.62f),
    unfocusedContainerColor = CodexPanel.copy(alpha = 0.44f),
    focusedTextColor = MaterialTheme.colorScheme.onSurface,
    unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
    cursorColor = CodexAccent,
)
