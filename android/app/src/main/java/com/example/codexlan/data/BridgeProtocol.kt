package com.example.codexlan.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

val ProtocolJson: Json = Json {
    classDiscriminator = "type"
    ignoreUnknownKeys = true
    encodeDefaults = true
}

@Serializable
sealed interface ClientMessage

@Serializable
@SerialName("pairing.claim")
data class PairingClaim(
    val pairingToken: String,
    val deviceName: String,
) : ClientMessage

@Serializable
@SerialName("auth.resume")
data class AuthResume(
    val deviceToken: String,
) : ClientMessage

@Serializable
@SerialName("session.start")
data class SessionStart(
    val sessionId: String? = null,
) : ClientMessage

@Serializable
@SerialName("prompt.send")
data class PromptSend(
    val sessionId: String,
    val prompt: String,
) : ClientMessage

@Serializable
@SerialName("run.cancel")
data class RunCancel(
    val sessionId: String,
    val runId: String,
) : ClientMessage

@Serializable
@SerialName("approval.decision")
data class ApprovalDecision(
    val sessionId: String,
    val approvalId: String,
    val decision: String,
) : ClientMessage

@Serializable
@SerialName("ping")
data class Ping(
    val nonce: String? = null,
) : ClientMessage

@Serializable
sealed interface ServerMessage

@Serializable
@SerialName("pairing.accepted")
data class PairingAccepted(
    val version: Int,
    val deviceId: String,
    val deviceToken: String,
    val sessionId: String,
) : ServerMessage

@Serializable
@SerialName("auth.accepted")
data class AuthAccepted(
    val version: Int,
    val deviceId: String,
    val sessionId: String,
) : ServerMessage

@Serializable
@SerialName("session.started")
data class SessionStarted(
    val sessionId: String,
) : ServerMessage

@Serializable
@SerialName("run.started")
data class RunStarted(
    val sessionId: String,
    val runId: String,
) : ServerMessage

@Serializable
@SerialName("output.delta")
data class OutputDelta(
    val sessionId: String,
    val runId: String,
    val stream: String,
    val text: String,
) : ServerMessage

@Serializable
@SerialName("status")
data class BridgeStatus(
    val status: String,
    val sessionId: String? = null,
    val runId: String? = null,
    val detail: String? = null,
) : ServerMessage

@Serializable
@SerialName("approval.requested")
data class ApprovalRequested(
    val sessionId: String,
    val approvalId: String,
    val title: String,
    val body: String,
    val riskLevel: String,
) : ServerMessage

@Serializable
@SerialName("diff.available")
data class DiffAvailable(
    val sessionId: String,
    val files: List<DiffFile>,
) : ServerMessage

@Serializable
data class DiffFile(
    val path: String,
    val status: String,
)

@Serializable
@SerialName("run.completed")
data class RunCompleted(
    val sessionId: String,
    val runId: String,
    val exitCode: Int? = null,
) : ServerMessage

@Serializable
@SerialName("error")
data class BridgeError(
    val code: String,
    val message: String,
) : ServerMessage

@Serializable
@SerialName("pong")
data class Pong(
    val nonce: String? = null,
) : ServerMessage

@Serializable
data class PairingPayload(
    val version: Int,
    val url: String,
    val pairingToken: String,
    val hostId: String,
    val insecureDevMode: Boolean,
)
