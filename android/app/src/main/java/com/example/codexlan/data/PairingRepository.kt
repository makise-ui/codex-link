package com.example.codexlan.data

class PairingRepository(
    private val json: kotlinx.serialization.json.Json = ProtocolJson,
) {
    fun parsePairingPayload(raw: String): Result<PairingPayload> = runCatching {
        json.decodeFromString(PairingPayload.serializer(), raw.trim())
    }.mapCatching { payload ->
        require(payload.version == 1) { "Unsupported pairing payload version: ${payload.version}" }
        require(payload.url.startsWith("ws://") || payload.url.startsWith("wss://")) { "Pairing URL must start with ws:// or wss://" }
        require(payload.pairingToken.length >= 16) { "Pairing token is too short" }
        payload
    }
}
