package com.example.codexlan

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.example.codexlan.data.AuthAccepted
import com.example.codexlan.data.AuthResume
import com.example.codexlan.data.BridgeClient
import com.example.codexlan.data.BridgeError
import com.example.codexlan.data.BridgeEvent
import com.example.codexlan.data.BridgeStatus
import com.example.codexlan.data.DiffAvailable
import com.example.codexlan.data.OutputDelta
import com.example.codexlan.data.PairingAccepted
import com.example.codexlan.data.PairingClaim
import com.example.codexlan.data.PairingRepository
import com.example.codexlan.data.PromptSend
import com.example.codexlan.data.RunCancel
import com.example.codexlan.data.RunCompleted
import com.example.codexlan.data.RunStarted
import com.example.codexlan.data.SecureTokenStore
import com.example.codexlan.data.ServerMessage
import com.example.codexlan.data.SessionStarted
import com.example.codexlan.data.StoredBridgeCredentials
import com.example.codexlan.domain.ChatLine
import com.example.codexlan.domain.ChatRole
import com.example.codexlan.domain.ConnectionState
import com.example.codexlan.ui.chat.ChatScreen
import com.example.codexlan.ui.pairing.PairingScreen
import com.example.codexlan.ui.theme.CodexBackground
import kotlinx.coroutines.launch
import java.util.UUID

private data class AppUiState(
    val connectionState: ConnectionState = ConnectionState.Disconnected,
    val statusText: String = "Not connected",
    val savedCredentials: StoredBridgeCredentials? = null,
    val sessionId: String? = null,
    val activeRunId: String? = null,
    val messages: List<ChatLine> = emptyList(),
)

@Composable
fun CodexLanApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val tokenStore = remember { SecureTokenStore(context) }
    val pairingRepository = remember { PairingRepository() }
    val bridgeClient = remember { BridgeClient() }
    val savedAtStartup = remember { tokenStore.load() }

    var state by remember {
        mutableStateOf(
            AppUiState(
                savedCredentials = savedAtStartup,
                sessionId = savedAtStartup?.sessionId,
            ),
        )
    }

    fun appendLine(role: ChatRole, text: String, runId: String? = null, stream: String? = null) {
        state = state.copy(
            messages = state.messages + ChatLine(
                id = UUID.randomUUID().toString(),
                role = role,
                text = text,
                runId = runId,
                stream = stream,
            ),
        )
    }

    fun appendOutput(delta: OutputDelta) {
        val last = state.messages.lastOrNull()
        val merged = if (last?.role == ChatRole.Assistant && last.runId == delta.runId && last.stream == delta.stream) {
            state.messages.dropLast(1) + last.copy(text = last.text + delta.text)
        } else {
            state.messages + ChatLine(
                id = UUID.randomUUID().toString(),
                role = ChatRole.Assistant,
                text = delta.text,
                runId = delta.runId,
                stream = delta.stream,
            )
        }
        state = state.copy(messages = merged)
    }

    fun handleServerMessage(message: ServerMessage, urlForPairing: String? = null) {
        when (message) {
            is PairingAccepted -> {
                val url = urlForPairing ?: state.savedCredentials?.url ?: return
                val credentials = StoredBridgeCredentials(
                    url = url,
                    deviceId = message.deviceId,
                    deviceToken = message.deviceToken,
                    sessionId = message.sessionId,
                )
                tokenStore.save(credentials)
                state = state.copy(
                    connectionState = ConnectionState.Authenticated,
                    statusText = "Paired with host",
                    savedCredentials = credentials,
                    sessionId = message.sessionId,
                )
                appendLine(ChatRole.System, "Paired with Codex host ${message.deviceId.take(8)}")
            }
            is AuthAccepted -> {
                state = state.copy(
                    connectionState = ConnectionState.Authenticated,
                    statusText = "Authenticated",
                    sessionId = message.sessionId,
                )
                appendLine(ChatRole.System, "Reconnected to saved Codex host ${message.deviceId.take(8)}")
            }
            is SessionStarted -> {
                state = state.copy(sessionId = message.sessionId, statusText = "Session started")
            }
            is RunStarted -> {
                state = state.copy(activeRunId = message.runId, statusText = "Running")
            }
            is OutputDelta -> appendOutput(message)
            is BridgeStatus -> {
                val activeRun = when (message.status) {
                    "running", "cancelling" -> message.runId ?: state.activeRunId
                    "cancelled", "completed", "failed" -> null
                    else -> state.activeRunId
                }
                state = state.copy(
                    statusText = message.detail ?: message.status,
                    activeRunId = activeRun,
                )
            }
            is RunCompleted -> {
                state = state.copy(activeRunId = null, statusText = "Run completed")
            }
            is BridgeError -> {
                state = state.copy(statusText = "${message.code}: ${message.message}")
                appendLine(ChatRole.Error, message.message)
            }
            is DiffAvailable -> appendLine(ChatRole.System, "Diff available for ${message.files.size} file(s). Diff viewer is reserved for the next milestone.")
            else -> appendLine(ChatRole.System, "Received ${message::class.simpleName}")
        }
    }

    fun handleBridgeEvent(event: BridgeEvent, urlForPairing: String? = null, onOpen: (() -> Unit)? = null) {
        when (event) {
            BridgeEvent.Connecting -> state = state.copy(connectionState = ConnectionState.Connecting, statusText = "Connecting…")
            BridgeEvent.Open -> {
                state = state.copy(connectionState = ConnectionState.Connected, statusText = "Socket open")
                onOpen?.invoke()
            }
            is BridgeEvent.Message -> handleServerMessage(event.message, urlForPairing)
            is BridgeEvent.Closed -> state = state.copy(connectionState = ConnectionState.Disconnected, statusText = "Closed: ${event.reason}", activeRunId = null)
            is BridgeEvent.Failure -> {
                state = state.copy(connectionState = ConnectionState.Failed, statusText = event.message, activeRunId = null)
                appendLine(ChatRole.Error, event.message)
            }
        }
    }

    fun pair(payloadText: String, deviceName: String) {
        val payload = pairingRepository.parsePairingPayload(payloadText).getOrElse { error ->
            state = state.copy(statusText = error.message ?: "Invalid pairing payload")
            appendLine(ChatRole.Error, error.message ?: "Invalid pairing payload")
            return
        }

        bridgeClient.connect(payload.url) { event ->
            scope.launch {
                handleBridgeEvent(
                    event = event,
                    urlForPairing = payload.url,
                    onOpen = {
                        bridgeClient.send(PairingClaim(payload.pairingToken, deviceName))
                    },
                )
            }
        }
    }

    fun reconnect() {
        val credentials = state.savedCredentials ?: return
        bridgeClient.connect(credentials.url) { event ->
            scope.launch {
                handleBridgeEvent(
                    event = event,
                    onOpen = { bridgeClient.send(AuthResume(credentials.deviceToken)) },
                )
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose { bridgeClient.close() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(CodexBackground),
    ) {
        if (state.connectionState == ConnectionState.Authenticated) {
            ChatScreen(
                connectionState = state.connectionState,
                statusText = state.statusText,
                sessionId = state.sessionId,
                activeRunId = state.activeRunId,
                messages = state.messages,
                onSendPrompt = { prompt ->
                    val sessionId = state.sessionId ?: return@ChatScreen
                    appendLine(ChatRole.User, prompt)
                    bridgeClient.send(PromptSend(sessionId, prompt))
                },
                onCancel = {
                    val sessionId = state.sessionId
                    val runId = state.activeRunId
                    if (sessionId != null && runId != null) {
                        bridgeClient.send(RunCancel(sessionId, runId))
                    }
                },
                onDisconnect = {
                    bridgeClient.close()
                    state = state.copy(connectionState = ConnectionState.Disconnected, statusText = "Disconnected", activeRunId = null)
                },
            )
        } else {
            PairingScreen(
                connectionState = state.connectionState,
                statusText = state.statusText,
                savedCredentials = state.savedCredentials,
                onPair = ::pair,
                onReconnect = ::reconnect,
                onForgetSaved = {
                    tokenStore.clear()
                    state = state.copy(savedCredentials = null, sessionId = null, statusText = "Saved host forgotten")
                },
            )
        }
    }
}
